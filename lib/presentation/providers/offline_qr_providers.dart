import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/offline_attendance_service.dart';
import '../../services/offline_qr_store.dart';
import 'repository_providers.dart';

final offlineQrStoreProvider = FutureProvider<OfflineQrStore>((ref) async {
  return OfflineQrStore.open();
});

final offlineAttendanceServiceProvider =
    Provider<OfflineAttendanceService?>((ref) {
  final storeAsync = ref.watch(offlineQrStoreProvider);
  return storeAsync.when(
    data: (store) => OfflineAttendanceService(
      events: ref.watch(eventRepositoryProvider),
      store: store,
    ),
    loading: () => null,
    error: (_, _) => null,
  );
});

/// Bump to force [pendingAttendanceCountProvider] to re-read SharedPreferences.
final pendingAttendanceTickProvider = StateProvider<int>((ref) => 0);

/// Number of offline attendance scans waiting to reach the server.
final pendingAttendanceCountProvider = Provider<int>((ref) {
  ref.watch(pendingAttendanceTickProvider);
  ref.watch(offlineQrStoreProvider);
  return ref.watch(offlineAttendanceServiceProvider)?.pendingCount() ?? 0;
});

void bumpPendingAttendanceTick(WidgetRef ref) {
  ref.read(pendingAttendanceTickProvider.notifier).state++;
}
