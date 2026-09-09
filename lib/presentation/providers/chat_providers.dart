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
      await _ensureClanChannels(repo, forUserId: uid);
    } else if (arg == ConversationType.city) {
      try {
        await repo.openCityChat();
      } catch (_) {}
    }

    // If session flipped mid-await, don't publish the wrong inbox.
    final uidAfter = ref.read(supabaseClientProvider).auth.currentUser?.id;
    if (uidAfter != uid) return const [];

    final list = await repo.fetchConversations(type: arg);

    final uidFinal = ref.read(supabaseClientProvider).auth.currentUser?.id;
    if (uidFinal != uid) return const [];

    unawaited(ref.read(folderUnreadProvider.notifier).refresh(silent: true));

    if (_boundUserId != uid) {
      _tearDownInboxChannel();
      _boundUserId = uid;
      _channel = repo.subscribeConversationsInbox(
        onChange: () {
          final liveUid =
              ref.read(supabaseClientProvider).auth.currentUser?.id;
          if (liveUid != _boundUserId) return;
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 400), () {
            refresh(silent: true);
            unawaited(
              ref.read(folderUnreadProvider.notifier).refresh(silent: true),
            );
          });
        },
      );
    }

    return list;
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
      if (!stillSame) return;
      for (final clanId in clanIds) {
        await repo.openClanChat(clanId);
        final role = await ref.read(myClanRoleProvider(clanId).future);
        if (role == ClanRole.leader ||
            role == ClanRole.officer ||
            role == ClanRole.trainer) {
          try {
            await repo.openClanOfficersChat(clanId);
          } catch (_) {}
        }
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
      final list =
          await ref.read(chatRepositoryProvider).fetchConversations(type: arg);
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
}

/// Alias used by chat message notifier refresh.
final conversationsListProvider = conversationsByTypeProvider;

final conversationDetailProvider = AsyncNotifierProvider.family<
    ConversationDetailNotifier, ConversationDetail, String>(
  ConversationDetailNotifier.new,
);

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
    _channel = _ref.read(chatRepositoryProvider).subscribeMessages(
          conversationId: conversationId,
          onInsert: _onRealtimeMessage,
        );
    await _ref.read(chatRepositoryProvider).markRead(conversationId);
    unawaited(
      _ref.read(folderUnreadProvider.notifier).refresh(silent: true),
    );
  }

  Future<void> loadInitial() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final messages = await _ref
          .read(chatRepositoryProvider)
          .fetchMessages(conversationId: conversationId);
      if (!mounted) return;
      state = state.copyWith(
        messages: messages,
        loading: false,
        hasMore: messages.length >= 40,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: e.toString());
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
        messages: [...older, ...state.messages],
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

  Future<void> _handleRealtimeMessage(ChatMessage message) async {
    final enriched =
        await _ref.read(chatRepositoryProvider).enrichSender(message);
    if (!mounted) return;
    final exists = state.messages.any((m) => m.id == enriched.id);
    if (exists) return;

    final withoutPending = state.messages
        .where(
          (m) => !(m.pending &&
              m.senderId == enriched.senderId &&
              m.text == enriched.text),
        )
        .toList();

    state = state.copyWith(messages: [...withoutPending, enriched]);

    final uid = _ref.read(authRepositoryProvider).currentUser?.id;
    if (uid != null && enriched.senderId != uid) {
      _markReadDebounce?.cancel();
      _markReadDebounce = Timer(const Duration(milliseconds: 300), () {
        unawaited(() async {
          await _ref.read(chatRepositoryProvider).markRead(conversationId);
          await _ref
              .read(folderUnreadProvider.notifier)
              .refresh(silent: true);
        }());
      });
    }

    for (final t in ConversationType.values) {
      _ref.read(conversationsByTypeProvider(t).notifier).refresh(silent: true);
    }
  }

  Future<bool> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    final uid = _ref.read(authRepositoryProvider).currentUser?.id;
    if (uid == null) return false;

    final me = _ref.read(currentProfileProvider).valueOrNull;
    final tempId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = ChatMessage(
      id: tempId,
      conversationId: conversationId,
      senderId: uid,
      text: trimmed,
      createdAt: DateTime.now(),
      pending: true,
      senderNickname: me?.nickname,
      senderAvatarUrl: me?.avatarUrl,
    );

    state = state.copyWith(
      messages: [...state.messages, optimistic],
      sending: true,
      clearError: true,
    );

    try {
      var saved = await _ref.read(chatRepositoryProvider).sendMessage(
            conversationId: conversationId,
            text: trimmed,
          );
      saved = saved.copyWith(
        senderNickname: saved.senderNickname ?? me?.nickname,
        senderAvatarUrl: saved.senderAvatarUrl ?? me?.avatarUrl,
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
  }) async {
    final uid = _ref.read(authRepositoryProvider).currentUser?.id;
    if (uid == null) return false;
    if (bytes.isEmpty || durationMs < 500) return false;

    final me = _ref.read(currentProfileProvider).valueOrNull;
    final tempId = 'local-voice-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = ChatMessage(
      id: tempId,
      conversationId: conversationId,
      senderId: uid,
      text: '',
      createdAt: DateTime.now(),
      pending: true,
      messageType: ChatMessageType.voice,
      audioDurationMs: durationMs,
      senderNickname: me?.nickname,
      senderAvatarUrl: me?.avatarUrl,
    );

    state = state.copyWith(
      messages: [...state.messages, optimistic],
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
          );
      saved = saved.copyWith(
        senderNickname: saved.senderNickname ?? me?.nickname,
        senderAvatarUrl: saved.senderAvatarUrl ?? me?.avatarUrl,
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

  Future<bool> sendImage({required Uint8List bytes}) async {
    final uid = _ref.read(authRepositoryProvider).currentUser?.id;
    if (uid == null) return false;
    if (bytes.isEmpty) return false;

    final me = _ref.read(currentProfileProvider).valueOrNull;
    final tempId = 'local-image-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = ChatMessage(
      id: tempId,
      conversationId: conversationId,
      senderId: uid,
      text: '',
      createdAt: DateTime.now(),
      pending: true,
      messageType: ChatMessageType.image,
      senderNickname: me?.nickname,
      senderAvatarUrl: me?.avatarUrl,
    );

    state = state.copyWith(
      messages: [...state.messages, optimistic],
      sending: true,
      clearError: true,
    );

    try {
      final url = await _ref.read(chatImageStorageServiceProvider).uploadImage(
            userId: uid,
            conversationId: conversationId,
            bytes: bytes,
          );
      var saved = await _ref.read(chatRepositoryProvider).sendImageMessage(
            conversationId: conversationId,
            imageUrl: url,
          );
      saved = saved.copyWith(
        senderNickname: saved.senderNickname ?? me?.nickname,
        senderAvatarUrl: saved.senderAvatarUrl ?? me?.avatarUrl,
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
      messages: deduped.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      sending: false,
    );
    for (final t in ConversationType.values) {
      _ref.read(conversationsByTypeProvider(t).notifier).refresh(silent: true);
    }
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
