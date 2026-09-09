import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/app_notification.dart';
import 'auth_providers.dart';
import 'repository_providers.dart';

final pendingAppNotificationsProvider = AsyncNotifierProvider<
    PendingAppNotificationsNotifier, List<AppNotification>>(
  PendingAppNotificationsNotifier.new,
);

class PendingAppNotificationsNotifier
    extends AsyncNotifier<List<AppNotification>> {
  RealtimeChannel? _channel;

  @override
  Future<List<AppNotification>> build() async {
    ref.onDispose(() {
      final channel = _channel;
      _channel = null;
      if (channel != null) {
        unawaited(ref.read(supabaseClientProvider).removeChannel(channel));
      }
    });

    ref.watch(authStateProvider);
    final uid = ref.watch(supabaseClientProvider).auth.currentUser?.id;
    if (uid == null) return const [];

    _channel ??= ref.read(notificationRepositoryProvider).subscribe(
          userId: uid,
          onChange: () {
            unawaited(refresh(silent: true));
          },
        );

    return ref.read(notificationRepositoryProvider).fetchPending();
  }

  Future<void> refresh({bool silent = false}) async {
    if (!silent) state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(notificationRepositoryProvider).fetchPending(),
    );
  }

  Future<void> markSeen(String id) async {
    await ref.read(notificationRepositoryProvider).markSeen(id);
    final current = state.valueOrNull ?? const <AppNotification>[];
    state = AsyncData([
      for (final n in current)
        if (n.id != id) n,
    ]);
  }
}

final conversationNotificationsMutedProvider =
    FutureProvider.family<bool, String>((ref, conversationId) async {
  ref.watch(authStateProvider);
  return ref
      .read(notificationRepositoryProvider)
      .isConversationMuted(conversationId);
});
