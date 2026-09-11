import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/presence.dart';
import '../../services/push_notification_service.dart';
import 'auth_providers.dart';
import 'offline_qr_providers.dart';

/// Keeps `profiles.last_seen_at` fresh while the app is in foreground.
final presenceHeartbeatProvider = Provider<void>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return;

  final repo = ref.read(profileRepositoryProvider);
  Timer? timer;

  Future<void> beat() async {
    await repo.touchPresence();
  }

  unawaited(beat());
  timer = Timer.periodic(const Duration(seconds: 60), (_) {
    unawaited(beat());
  });

  ref.onDispose(() {
    timer?.cancel();
  });
});

/// Live last-seen for a user (polls while watched).
final userLastSeenProvider =
    StreamProvider.autoDispose.family<DateTime?, String>((ref, userId) async* {
  final repo = ref.watch(profileRepositoryProvider);

  Future<DateTime?> load() => repo.fetchLastSeen(userId);

  yield await load();
  yield* Stream.periodic(const Duration(seconds: 30)).asyncMap((_) => load());
});

final userOnlineProvider =
    Provider.autoDispose.family<bool, String>((ref, userId) {
  final lastSeen = ref.watch(userLastSeenProvider(userId)).valueOrNull;
  return Presence.isOnline(lastSeen);
});

/// Hooks app lifecycle → immediate heartbeat on resume.
class PresenceLifecycle extends ConsumerStatefulWidget {
  const PresenceLifecycle({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PresenceLifecycle> createState() => _PresenceLifecycleState();
}

class _PresenceLifecycleState extends ConsumerState<PresenceLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final user = ref.read(currentUserProvider);
      if (user != null) {
        unawaited(ref.read(profileRepositoryProvider).touchPresence());
        unawaited(PushNotificationService.instance.requestDrain());
        final offline = ref.read(offlineAttendanceServiceProvider);
        if (offline != null) {
          unawaited(() async {
            await offline.syncPending();
            bumpPendingAttendanceTick(ref);
          }());
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(presenceHeartbeatProvider);
    return widget.child;
  }
}
