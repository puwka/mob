import 'dart:async';

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
    return ref.read(chatRepositoryProvider).fetchUnreadByType();
  }

  Future<void> refresh({bool silent = false}) async {
    if (!silent) state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(chatRepositoryProvider).fetchUnreadByType(),
    );
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

  @override
  Future<List<ConversationPreview>> build(ConversationType arg) async {
    ref.onDispose(() {
      _debounce?.cancel();
      final channel = _channel;
      _channel = null;
      if (channel != null) {
        unawaited(ref.read(supabaseClientProvider).removeChannel(channel));
      }
    });

    final repo = ref.read(chatRepositoryProvider);
    if (arg == ConversationType.clan) {
      await _ensureClanChannels(repo);
    }

    final list = await repo.fetchConversations(type: arg);
    unawaited(ref.read(folderUnreadProvider.notifier).refresh(silent: true));

    _channel ??= repo.subscribeConversationsInbox(
      onChange: () {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 400), () {
          refresh(silent: true);
          unawaited(
            ref.read(folderUnreadProvider.notifier).refresh(silent: true),
          );
        });
      },
    );

    return list;
  }

  Future<void> _ensureClanChannels(ChatRepository repo) async {
    try {
      final clanIds = await repo.fetchMyClanIds();
      for (final clanId in clanIds) {
        await repo.openClanChat(clanId);
        final role = await ref.read(myClanRoleProvider(clanId).future);
        if (role == ClanRole.leader || role == ClanRole.officer) {
          try {
            await repo.openClanOfficersChat(clanId);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> refresh({bool silent = false}) async {
    if (!silent) state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(chatRepositoryProvider).fetchConversations(type: arg),
    );
    unawaited(ref.read(folderUnreadProvider.notifier).refresh(silent: true));
  }
}

/// Alias used by chat message notifier refresh.
final conversationsListProvider = conversationsByTypeProvider;

final conversationDetailProvider = AsyncNotifierProvider.family<
    ConversationDetailNotifier, ConversationDetail, String>(
  ConversationDetailNotifier.new,
);

class ConversationDetailNotifier
    extends FamilyAsyncNotifier<ConversationDetail, String> {
  @override
  Future<ConversationDetail> build(String arg) {
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

final chatMessagesProvider = StateNotifierProvider.family<
    ChatMessagesNotifier, ChatMessagesState, String>(
  (ref, conversationId) => ChatMessagesNotifier(ref, conversationId),
);

class ChatMessagesNotifier extends StateNotifier<ChatMessagesState> {
  ChatMessagesNotifier(this._ref, this.conversationId)
      : super(const ChatMessagesState(loading: true)) {
    _init();
  }

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
    final exists = state.messages.any((m) => m.id == message.id);
    if (exists) return;

    final withoutPending = state.messages
        .where(
          (m) => !(m.pending &&
              m.senderId == message.senderId &&
              m.text == message.text),
        )
        .toList();

    state = state.copyWith(messages: [...withoutPending, message]);

    final uid = _ref.read(authRepositoryProvider).currentUser?.id;
    if (uid != null && message.senderId != uid) {
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

    _ref
        .read(conversationsByTypeProvider(ConversationType.user).notifier)
        .refresh(silent: true);
    _ref
        .read(conversationsByTypeProvider(ConversationType.market).notifier)
        .refresh(silent: true);
    _ref
        .read(conversationsByTypeProvider(ConversationType.clan).notifier)
        .refresh(silent: true);
  }

  Future<bool> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    final uid = _ref.read(authRepositoryProvider).currentUser?.id;
    if (uid == null) return false;

    final tempId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = ChatMessage(
      id: tempId,
      conversationId: conversationId,
      senderId: uid,
      text: trimmed,
      createdAt: DateTime.now(),
      pending: true,
    );

    state = state.copyWith(
      messages: [...state.messages, optimistic],
      sending: true,
      clearError: true,
    );

    try {
      final saved = await _ref.read(chatRepositoryProvider).sendMessage(
            conversationId: conversationId,
            text: trimmed,
          );
      if (!mounted) return true;
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
        _ref
            .read(conversationsByTypeProvider(t).notifier)
            .refresh(silent: true);
      }
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
