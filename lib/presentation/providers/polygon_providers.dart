import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/polygon.dart';
import 'auth_providers.dart';
import 'repository_providers.dart';

final myPolygonsProvider =
    AsyncNotifierProvider<MyPolygonsNotifier, List<PolygonVenue>>(
  MyPolygonsNotifier.new,
);

class MyPolygonsNotifier extends AsyncNotifier<List<PolygonVenue>> {
  @override
  Future<List<PolygonVenue>> build() async {
    ref.watch(authStateProvider);
    final uid = ref.watch(supabaseClientProvider).auth.currentUser?.id;
    if (uid == null) return const [];
    return ref.read(polygonRepositoryProvider).fetchMine();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final uid = ref.read(supabaseClientProvider).auth.currentUser?.id;
      if (uid == null) return const <PolygonVenue>[];
      return ref.read(polygonRepositoryProvider).fetchMine();
    });
  }
}
