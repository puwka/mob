import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/app_exception.dart';
import '../../domain/models/conversation.dart';
import '../../domain/models/dating.dart';
import 'auth_providers.dart';
import 'chat_providers.dart';
import 'repository_providers.dart';

/// Optional city filter for dating feed (`null` = all cities).
final datingCityFilterProvider = StateProvider<String?>((ref) => null);

final datingFeedProvider =
    AsyncNotifierProvider<DatingFeedNotifier, List<DatingCandidate>>(
  DatingFeedNotifier.new,
);

class DatingFeedNotifier extends AsyncNotifier<List<DatingCandidate>> {
  @override
  Future<List<DatingCandidate>> build() async {
    ref.watch(authStateProvider);
    ref.watch(datingCityFilterProvider);
    final uid = ref.watch(supabaseClientProvider).auth.currentUser?.id;
    if (uid == null) return const [];
    final city = ref.read(datingCityFilterProvider);
    return ref.read(datingRepositoryProvider).fetchCandidates(
          limit: 20,
          city: city,
        );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final uid = ref.read(supabaseClientProvider).auth.currentUser?.id;
      if (uid == null) return const <DatingCandidate>[];
      final city = ref.read(datingCityFilterProvider);
      return ref.read(datingRepositoryProvider).fetchCandidates(
            limit: 20,
            city: city,
          );
    });
  }

  DatingCandidate? get current {
    final list = state.valueOrNull;
    if (list == null || list.isEmpty) return null;
    return list.first;
  }

  Future<DatingActionResult?> act(DatingActionType action) async {
    final candidate = current;
    if (candidate == null) return null;

    final previous = state.valueOrNull ?? const <DatingCandidate>[];
    state = AsyncData([
      for (final c in previous)
        if (c.id != candidate.id) c,
    ]);

    try {
      final result = await ref.read(datingRepositoryProvider).processAction(
            targetUserId: candidate.id,
            action: action,
          );

      final remaining = state.valueOrNull ?? const <DatingCandidate>[];
      if (remaining.length < 5) {
        await _topUp(excludeIds: {
          candidate.id,
          ...remaining.map((c) => c.id),
        });
      }

      if (result.matched || result.action == DatingActionType.like) {
        ref.invalidate(datingMatchesProvider);
        ref.invalidate(pendingDatingNotificationsProvider);
        if (result.matched) {
          ref.invalidate(conversationsByTypeProvider(ConversationType.dating));
          unawaited(
            ref.read(folderUnreadProvider.notifier).refresh(silent: true),
          );
        }
      }
      return result;
    } catch (e) {
      state = AsyncData([
        candidate,
        ...previous.where((c) => c.id != candidate.id),
      ]);
      if (e is AppException) rethrow;
      throw AppException(e.toString());
    }
  }

  Future<void> _topUp({required Set<String> excludeIds}) async {
    try {
      final city = ref.read(datingCityFilterProvider);
      final fresh = await ref.read(datingRepositoryProvider).fetchCandidates(
            limit: 20,
            city: city,
          );
      final existing = state.valueOrNull ?? const <DatingCandidate>[];
      final seen = <String>{
        ...excludeIds,
        ...existing.map((c) => c.id),
      };
      final merged = [
        ...existing,
        for (final c in fresh)
          if (!seen.contains(c.id)) c,
      ];
      state = AsyncData(merged);
    } catch (_) {}
  }
}

final datingMatchesProvider =
    AsyncNotifierProvider<DatingMatchesNotifier, List<DatingMatch>>(
  DatingMatchesNotifier.new,
);

class DatingMatchesNotifier extends AsyncNotifier<List<DatingMatch>> {
  @override
  Future<List<DatingMatch>> build() async {
    ref.watch(authStateProvider);
    final uid = ref.watch(supabaseClientProvider).auth.currentUser?.id;
    if (uid == null) return const [];
    return ref.read(datingRepositoryProvider).fetchMyMatches();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final uid = ref.read(supabaseClientProvider).auth.currentUser?.id;
      if (uid == null) return const <DatingMatch>[];
      return ref.read(datingRepositoryProvider).fetchMyMatches();
    });
  }
}

final pendingDatingNotificationsProvider = AsyncNotifierProvider<
    PendingDatingNotificationsNotifier, List<DatingNotification>>(
  PendingDatingNotificationsNotifier.new,
);

/// Alias kept for older call sites.
final pendingDatingMatchNotificationsProvider =
    pendingDatingNotificationsProvider;

class PendingDatingNotificationsNotifier
    extends AsyncNotifier<List<DatingNotification>> {
  RealtimeChannel? _channel;

  @override
  Future<List<DatingNotification>> build() async {
    ref.watch(authStateProvider);
    final client = ref.watch(supabaseClientProvider);
    final uid = client.auth.currentUser?.id;
    if (uid == null) return const [];

    ref.onDispose(() {
      final ch = _channel;
      _channel = null;
      if (ch != null) unawaited(client.removeChannel(ch));
    });

    _channel?.unsubscribe();
    _channel = client
        .channel('dating-notifications-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'dating_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (_) {
            unawaited(refresh(silent: true));
          },
        )
        .subscribe();

    return ref.read(datingRepositoryProvider).fetchPendingNotifications();
  }

  Future<void> refresh({bool silent = false}) async {
    if (!silent) state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final uid = ref.read(supabaseClientProvider).auth.currentUser?.id;
      if (uid == null) return const <DatingNotification>[];
      return ref.read(datingRepositoryProvider).fetchPendingNotifications();
    });
  }

  Future<void> markSeen(String notificationId) async {
    await ref.read(datingRepositoryProvider).markNotificationSeen(notificationId);
    final current = state.valueOrNull ?? const <DatingNotification>[];
    state = AsyncData([
      for (final n in current)
        if (n.notificationId != notificationId) n,
    ]);
  }
}
