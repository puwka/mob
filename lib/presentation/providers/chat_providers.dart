import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/app_exception.dart';
import '../../data/repositories/chat_repository.dart';
import '../../domain/models/clan.dart';
import '../../domain/models/conversation.dart';
import 'auth_providers.dart';
import 'clan_providers.dart';
import 'repository_providers.dart';

/// Kept for call sites that open a chat from market / profile / clan.
final chatFolderProvider =
    StateProvider<ConversationType>((ref) => ConversationType.user);

final folderUnreadProvider =
    AsyncNotifierProvider<FolderUnreadNotifier, Map<ConversationType, int>>(
  FolderUnreadNotifier.new,
);

class FolderUnreadNotifier
    extends AsyncNotifier<Map<ConversationType, int>> {
  @override
  Future<Map<ConversationType, int>> build() {
    ref.watch(authStateProvider);
    final uid = ref.watch(supabaseClientProvider).auth.currentUser?.id;
    if (uid == null) {
      return Future.value({
        for (final t in ConversationType.values) t: 0,
      });
    }
    return ref.read(chatRepositoryProvider).fetchUnreadByType();
  }

  Future<void> refresh({bool silent = false}) async {
    if (!silent) state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final uid = ref.read(supabaseClientProvider).auth.currentUser?.id;
      if (uid == null) {
        return {for (final t in ConversationType.values) t: 0};
      }
      return ref.read(chatRepositoryProvider).fetchUnreadByType();
    });
  }
}

final conversationsByTypeProvider = AsyncNotifierProvider.family<
    ConversationsByTypeNotifier, List<ConversationPreview>, ConversationType>(
  ConversationsByTypeNotifier.new,
);

class ConversationsByTypeNotifier extends FamilyAsyncNotifier<
    List<ConversationPreview>, ConversationType> {
  RealtimeChannel? _channel;
  Timer? _debounce;
  String? _boundUserId;

  @override
  Future<List<ConversationPreview>> build(ConversationType arg) async {
    ref.onDispose(() {
      _debounce?.cancel();
      _debounce = null;
      final channel = _channel;
      _channel = null;
      _boundUserId = null;
      if (channel != null) {
        unawaited(ref.read(supabaseClientProvider).removeChannel(channel));
      }
    });

    // Depend on auth stream + live uid so account switches never reuse inbox.
    ref.watch(authStateProvider);
    final uid = ref.watch(supabaseClientProvider).auth.currentUser?.id;
    if (uid == null) {
      _tearDownInboxChannel();
      return const [];
    }

    // Drop previous account's list immediately (don't keep AsyncData while loading).
    if (_boundUserId != null && _boundUserId != uid) {
      _tearDownInboxChannel();
      state = const AsyncData([]);
    }

    final repo = ref.read(chatRepositoryProvider);
    if (arg == ConversationType.clan) {
      // Don't block inbox on opening clan channels.
      unawaited(_ensureClanChannels(repo, forUserId: uid));
    } else if (arg == ConversationType.city) {
      unawaited(() async {
        try {
          await repo.openCityChat();
        } catch (_) {}
      }());
    } else if (arg == ConversationType.event) {
      unawaited(() async {
        try {
          await repo.autoFinishPastEvents();
        } catch (_) {}
      }());
    }

    // If session flipped mid-await, don't publish the wrong inbox.
    // Auth flicker (uid briefly null) should keep the previous list.
    final uidAfter = ref.read(supabaseClientProvider).auth.currentUser?.id;
    if (uidAfter != uid) {
      if (uidAfter == null && state.hasValue) return state.requireValue;
      return const [];
    }

    final list = await repo.fetchConversations(type: arg);
    final visible = arg == ConversationType.clan
        ? await _visibleClanConversations(list)
        : list;

    final uidFinal = ref.read(supabaseClientProvider).auth.currentUser?.id;
    if (uidFinal != uid) {
      if (uidFinal == null && state.hasValue) return state.requireValue;
      return const [];
    }

    unawaited(ref.read(folderUnreadProvider.notifier).refresh(silent: true));

    if (_boundUserId != uid) {
      _tearDownInboxChannel();
      _boundUserId = uid;
      _channel = repo.subscribeConversationsInbox(
        channelKey: arg.name,
        onChange: () {
          final liveUid =
              ref.read(supabaseClientProvider).auth.currentUser?.id;
          if (liveUid != _boundUserId) return;
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 1200), () {
            refresh(silent: true);
            unawaited(
              ref.read(folderUnreadProvider.notifier).refresh(silent: true),
            );
          });
        },
      );
    }

    return visible;
  }

  void _tearDownInboxChannel() {
    _debounce?.cancel();
    _debounce = null;
    final old = _channel;
    _channel = null;
    _boundUserId = null;
    if (old != null) {
      unawaited(ref.read(supabaseClientProvider).removeChannel(old));
    }
  }

  Future<void> _ensureClanChannels(
    ChatRepository repo, {
    required String forUserId,
  }) async {
    try {
      final clanIds = await repo.fetchMyClanIds();
      final stillSame =
          ref.read(supabaseClientProvider).auth.currentUser?.id == forUserId;
      if (!stillSame || clanIds.isEmpty) return;

      await Future.wait([
        for (final clanId in clanIds) _openChannelsForClan(repo, clanId),
      ]);

      final live =
          ref.read(supabaseClientProvider).auth.currentUser?.id == forUserId;
      if (live) {
        unawaited(refresh(silent: true));
      }
    } catch (_) {}
  }

  Future<void> _openChannelsForClan(
    ChatRepository repo,
    String clanId,
  ) async {
    try {
      await repo.openClanChat(clanId);
    } catch (_) {}
    try {
      final role = await ref.read(myClanRoleProvider(clanId).future);
      if (role?.isLeadership == true) {
        await repo.openClanOfficersChat(clanId);
      }
    } catch (_) {}
  }

  Future<void> refresh({bool silent = false}) async {
    final uid = ref.read(supabaseClientProvider).auth.currentUser?.id;
    if (uid == null) {
      state = const AsyncData([]);
      return;
    }
    if (!silent) state = const AsyncLoading();
    try {
      var list =
          await ref.read(chatRepositoryProvider).fetchConversations(type: arg);
      if (arg == ConversationType.clan) {
        list = await _visibleClanConversations(list);
      }
      final live = ref.read(supabaseClientProvider).auth.currentUser?.id;
      if (live != uid) return;
      state = AsyncData(list);
    } catch (e, st) {
      final live = ref.read(supabaseClientProvider).auth.currentUser?.id;
      if (live != uid) return;
      state = AsyncError(e, st);
    }
    unawaited(ref.read(folderUnreadProvider.notifier).refresh(silent: true));
  }

  /// Hide clan chats the user is not allowed to see (stale membership).
  Future<List<ConversationPreview>> _visibleClanConversations(
    List<ConversationPreview> list,
  ) async {
    final out = <ConversationPreview>[];
    for (final c in list) {
      final clanId = c.clanId;
      if (clanId == null) continue;
      final role = await ref.read(myClanRoleProvider(clanId).future);
      if (role == null) continue;
      if (c.clanChannel == ClanChatChannel.officers && !role.isLeadership) {
        continue;
      }
      out.add(c);
    }
    return out;
  }
}

/// Alias used by chat message notifier refresh.
final conversationsListProvider = conversationsByTypeProvider;

final conversationDetailProvider = AsyncNotifierProvider.family<
    ConversationDetailNotifier, ConversationDetail, String>(
  ConversationDetailNotifier.new,
);

final conversationParticipantsProvider = FutureProvider.autoDispose
    .family<List<ConversationParticipant>, String>((ref, conversationId) {
  ref.watch(authStateProvider);
  return ref.read(chatRepositoryProvider).fetchParticipants(conversationId);
});

final chatMuteProvider =
    FutureProvider.autoDispose.family<ChatMuteInfo?, String>((ref, conversationId) {
  ref.watch(authStateProvider);
  return ref.read(chatRepositoryProvider).fetchMyMute(conversationId);
});

class ConversationDetailNotifier
    extends FamilyAsyncNotifier<ConversationDetail, String> {
  @override
  Future<ConversationDetail> build(String arg) {
    ref.watch(authStateProvider);
    final uid = ref.watch(supabaseClientProvider).auth.currentUser?.id;
    if (uid == null) {
      throw const AppException('Требуется авторизация');
    }
    return ref.read(chatRepositoryProvider).fetchConversation(arg);
  }
}

class ChatMessagesState {
  const ChatMessagesState({
    this.messages = const [],
    this.loading = false,
    this.loadingMore = false,
    this.hasMore = true,
    this.error,
    this.sending = false,
  });

  final List<ChatMessage> messages;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final String? error;
  final bool sending;

  ChatMessagesState copyWith({
    List<ChatMessage>? messages,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    String? error,
    bool clearError = false,
    bool? sending,
  }) {
    return ChatMessagesState(
      messages: messages ?? this.messages,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
      sending: sending ?? this.sending,
    );
  }
}

final chatMessagesProvider = StateNotifierProvider.autoDispose
    .family<ChatMessagesNotifier, ChatMessagesState, String>(
  (ref, conversationId) {
    ref.watch(authStateProvider);
    final uid = ref.watch(supabaseClientProvider).auth.currentUser?.id;
    if (uid == null) {
      return ChatMessagesNotifier.inactive(ref, conversationId);
    }
    return ChatMessagesNotifier(ref, conversationId);
  },
);

class ChatMessagesNotifier extends StateNotifier<ChatMessagesState> {
  ChatMessagesNotifier(this._ref, this.conversationId)
      : super(const ChatMessagesState(loading: true)) {
    _init();
  }

  ChatMessagesNotifier.inactive(this._ref, this.conversationId)
      : super(const ChatMessagesState());

  final Ref _ref;
  final String conversationId;
  RealtimeChannel? _channel;
  Timer? _markReadDebounce;

  Future<void> _init() async {
    await loadInitial();
    if (!mounted) return;
    _channel = _ref.read(chatRepositoryProvider).subscribeMessages(
          conversationId: conversationId,
          onInsert: _onRealtimeMessage,
        );
    // Don't block chat open on mark-read / badge refresh.
    unawaited(() async {
      try {
        await _ref.read(chatRepositoryProvider).markRead(conversationId);
        await _ref.read(folderUnreadProvider.notifier).refresh(silent: true);
      } catch (_) {}
    }());
  }

  List<ChatMessage> _sorted(Iterable<ChatMessage> messages) {
    final list = messages.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  Future<void> loadInitial() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final messages = await _ref
          .read(chatRepositoryProvider)
          .fetchMessages(conversationId: conversationId);
      if (!mounted) return;
      state = state.copyWith(
        messages: _sorted(messages),
        loading: false,
        hasMore: messages.length >= 40,
      );
    } catch (e) {
      // One retry — transient network / embed failures.
      try {
        final messages = await _ref
            .read(chatRepositoryProvider)
            .fetchMessages(conversationId: conversationId);
        if (!mounted) return;
        state = state.copyWith(
          messages: _sorted(messages),
          loading: false,
          hasMore: messages.length >= 40,
          clearError: true,
        );
      } catch (e2) {
        if (!mounted) return;
        state = state.copyWith(loading: false, error: e2.toString());
      }
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore || state.messages.isEmpty) return;
    state = state.copyWith(loadingMore: true);
    try {
      final oldest = state.messages.first.createdAt;
      final older = await _ref.read(chatRepositoryProvider).fetchMessages(
            conversationId: conversationId,
            before: oldest,
          );
      if (!mounted) return;
      state = state.copyWith(
        messages: _sorted([...older, ...state.messages]),
        loadingMore: false,
        hasMore: older.length >= 40,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(loadingMore: false);
    }
  }

  void _onRealtimeMessage(ChatMessage message) {
    if (!mounted) return;
    unawaited(_handleRealtimeMessage(message));
  }

  bool _matchesPending(ChatMessage pending, ChatMessage incoming) {
    if (!pending.pending || pending.senderId != incoming.senderId) {
      return false;
    }
    if (pending.messageType != incoming.messageType) return false;
    if (pending.isImage) {
      final pendingUrls = pending.resolvedImageUrls;
      final incomingUrls = incoming.resolvedImageUrls;
      if (pendingUrls.isEmpty) return true;
      if (pendingUrls.length != incomingUrls.length) return false;
      for (var i = 0; i < pendingUrls.length; i++) {
        if (pendingUrls[i] != incomingUrls[i]) return false;
      }
      return true;
    }
    if (pending.isVoice) {
      final pendingUrl = pending.audioUrl;
      final incomingUrl = incoming.audioUrl;
      if (pendingUrl == null || pendingUrl.isEmpty) return true;
      return pendingUrl == incomingUrl;
    }
    return pending.text == incoming.text;
  }

  void _refreshInboxForThisChat() {
    final detail =
        _ref.read(conversationDetailProvider(conversationId)).valueOrNull;
    final type = detail?.type;
    if (type != null) {
      _ref.read(conversationsByTypeProvider(type).notifier).refresh(silent: true);
    } else {
      for (final t in ConversationType.values) {
        _ref
            .read(conversationsByTypeProvider(t).notifier)
            .refresh(silent: true);
      }
    }
    unawaited(_ref.read(folderUnreadProvider.notifier).refresh(silent: true));
  }

  Future<void> _handleRealtimeMessage(ChatMessage message) async {
    if (!mounted) return;
    if (state.messages.any((m) => m.id == message.id)) return;

    // Show immediately (incl. image_url) — don't wait on profile enrich.
    final withoutPending = state.messages
        .where((m) => !_matchesPending(m, message))
        .toList();
    state = state.copyWith(messages: _sorted([...withoutPending, message]));

    final uid = _ref.read(authRepositoryProvider).currentUser?.id;
    if (uid != null && message.senderId != uid) {
      _markReadDebounce?.cancel();
      _markReadDebounce = Timer(const Duration(milliseconds: 300), () {
        unawaited(() async {
          try {
            await _ref.read(chatRepositoryProvider).markRead(conversationId);
            await _ref
                .read(folderUnreadProvider.notifier)
                .refresh(silent: true);
          } catch (_) {}
        }());
      });
    }

    _refreshInboxForThisChat();

    try {
      final enriched =
          await _ref.read(chatRepositoryProvider).enrichSender(message);
      if (!mounted) return;
      state = state.copyWith(
        messages: [
          for (final m in state.messages)
            if (m.id == enriched.id) enriched else m,
        ],
      );
    } catch (_) {}
  }

  Future<bool> send(String text, {String? replyToMessageId, ChatReplyPreview? replyTo}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    final uid = _ref.read(authRepositoryProvider).currentUser?.id;
    if (uid == null) return false;

    final me = _ref.read(currentProfileProvider).valueOrNull;
    final myClanRole = _myClanRoleInChat();
    final tempId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = ChatMessage(
      id: tempId,
      conversationId: conversationId,
      senderId: uid,
      text: trimmed,
      createdAt: DateTime.now().toUtc(),
      pending: true,
      senderNickname: me?.nickname,
      senderAvatarUrl: me?.avatarUrl,
      senderClanRole: myClanRole,
      replyToMessageId: replyToMessageId,
      replyTo: replyTo,
    );

    state = state.copyWith(
      messages: _sorted([...state.messages, optimistic]),
      sending: true,
      clearError: true,
    );

    try {
      var saved = await _ref.read(chatRepositoryProvider).sendMessage(
            conversationId: conversationId,
            text: trimmed,
            replyToMessageId: replyToMessageId,
          );
      saved = await _ref.read(chatRepositoryProvider).enrichSender(
            saved.copyWith(
              senderNickname: saved.senderNickname ?? me?.nickname,
              senderAvatarUrl: saved.senderAvatarUrl ?? me?.avatarUrl,
              senderClanRole: saved.senderClanRole ?? myClanRole,
              replyTo: saved.replyTo ?? replyTo,
            ),
          );
      if (!mounted) return true;
      _replaceOptimistic(tempId, saved);
      return true;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(
        sending: false,
        error: e is AppException ? e.message : e.toString(),
        messages: [
          for (final m in state.messages)
            if (m.id == tempId) m.copyWith(pending: false, failed: true) else m,
        ],
      );
      return false;
    }
  }

  Future<bool> sendVoice({
    required Uint8List bytes,
    required int durationMs,
    required String contentType,
    required String extension,
    String? replyToMessageId,
    ChatReplyPreview? replyTo,
  }) async {
    final uid = _ref.read(authRepositoryProvider).currentUser?.id;
    if (uid == null) return false;
    if (bytes.isEmpty || durationMs < 500) return false;

    final me = _ref.read(currentProfileProvider).valueOrNull;
    final myClanRole = _myClanRoleInChat();
    final tempId = 'local-voice-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = ChatMessage(
      id: tempId,
      conversationId: conversationId,
      senderId: uid,
      text: '',
      createdAt: DateTime.now().toUtc(),
      pending: true,
      messageType: ChatMessageType.voice,
      audioDurationMs: durationMs,
      senderNickname: me?.nickname,
      senderAvatarUrl: me?.avatarUrl,
      senderClanRole: myClanRole,
      replyToMessageId: replyToMessageId,
      replyTo: replyTo,
    );

    state = state.copyWith(
      messages: _sorted([...state.messages, optimistic]),
      sending: true,
      clearError: true,
    );

    try {
      final url = await _ref.read(chatVoiceStorageServiceProvider).uploadVoice(
            userId: uid,
            conversationId: conversationId,
            bytes: bytes,
            contentType: contentType,
            extension: extension,
          );
      var saved = await _ref.read(chatRepositoryProvider).sendVoiceMessage(
            conversationId: conversationId,
            audioUrl: url,
            durationMs: durationMs,
            replyToMessageId: replyToMessageId,
          );
      saved = await _ref.read(chatRepositoryProvider).enrichSender(
            saved.copyWith(
              senderNickname: saved.senderNickname ?? me?.nickname,
              senderAvatarUrl: saved.senderAvatarUrl ?? me?.avatarUrl,
              senderClanRole: saved.senderClanRole ?? myClanRole,
              replyTo: saved.replyTo ?? replyTo,
            ),
          );
      if (!mounted) return true;
      _replaceOptimistic(tempId, saved);
      return true;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(
        sending: false,
        error: e is AppException ? e.message : e.toString(),
        messages: [
          for (final m in state.messages)
            if (m.id == tempId) m.copyWith(pending: false, failed: true) else m,
        ],
      );
      return false;
    }
  }

  static const maxImagesPerMessage = 10;

  Future<bool> sendImage({
    required Uint8List bytes,
    String? replyToMessageId,
    ChatReplyPreview? replyTo,
  }) {
    return sendImages(
      images: [bytes],
      replyToMessageId: replyToMessageId,
      replyTo: replyTo,
    );
  }

  Future<bool> sendImages({
    required List<Uint8List> images,
    String? replyToMessageId,
    ChatReplyPreview? replyTo,
  }) async {
    final uid = _ref.read(authRepositoryProvider).currentUser?.id;
    if (uid == null) return false;

    final cleaned = [
      for (final b in images)
        if (b.isNotEmpty) b,
    ].take(maxImagesPerMessage).toList();
    if (cleaned.isEmpty) return false;

    final me = _ref.read(currentProfileProvider).valueOrNull;
    final myClanRole = _myClanRoleInChat();
    final tempId = 'local-image-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = ChatMessage(
      id: tempId,
      conversationId: conversationId,
      senderId: uid,
      text: '',
      createdAt: DateTime.now().toUtc(),
      pending: true,
      messageType: ChatMessageType.image,
      imageUrls: const [],
      senderNickname: me?.nickname,
      senderAvatarUrl: me?.avatarUrl,
      senderClanRole: myClanRole,
      replyToMessageId: replyToMessageId,
      replyTo: replyTo,
    );

    state = state.copyWith(
      messages: _sorted([...state.messages, optimistic]),
      sending: true,
      clearError: true,
    );

    try {
      final urls = await _ref.read(chatImageStorageServiceProvider).uploadImages(
            userId: uid,
            conversationId: conversationId,
            images: cleaned,
          );
      if (urls.isEmpty) {
        throw const AppException('Не удалось загрузить фото');
      }
      var saved = await _ref.read(chatRepositoryProvider).sendImageMessage(
            conversationId: conversationId,
            imageUrls: urls,
            replyToMessageId: replyToMessageId,
          );
      saved = await _ref.read(chatRepositoryProvider).enrichSender(
            saved.copyWith(
              senderNickname: saved.senderNickname ?? me?.nickname,
              senderAvatarUrl: saved.senderAvatarUrl ?? me?.avatarUrl,
              senderClanRole: saved.senderClanRole ?? myClanRole,
              replyTo: saved.replyTo ?? replyTo,
            ),
          );
      if (!mounted) return true;
      _replaceOptimistic(tempId, saved);
      return true;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(
        sending: false,
        error: e is AppException ? e.message : e.toString(),
        messages: [
          for (final m in state.messages)
            if (m.id == tempId) m.copyWith(pending: false, failed: true) else m,
        ],
      );
      return false;
    }
  }

  ClanRole? _myClanRoleInChat() {
    final detail =
        _ref.read(conversationDetailProvider(conversationId)).valueOrNull;
    if (detail == null ||
        detail.type != ConversationType.clan ||
        detail.clanId == null) {
      return null;
    }
    return _ref.read(myClanRoleProvider(detail.clanId!)).valueOrNull;
  }

  void _replaceOptimistic(String tempId, ChatMessage saved) {
    final next = [
      for (final m in state.messages)
        if (m.id == tempId) saved else m,
    ];
    final deduped = <String, ChatMessage>{};
    for (final m in next) {
      deduped[m.id] = m;
    }
    if (!deduped.containsKey(saved.id)) {
      deduped.remove(tempId);
      deduped[saved.id] = saved;
    } else {
      deduped.remove(tempId);
    }
    state = state.copyWith(
      messages: _sorted(deduped.values),
      sending: false,
    );
    _refreshInboxForThisChat();
  }

  @override
  void dispose() {
    _markReadDebounce?.cancel();
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      unawaited(_ref.read(supabaseClientProvider).removeChannel(channel));
    }
    super.dispose();
  }
}
