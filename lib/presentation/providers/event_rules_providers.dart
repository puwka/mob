import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/event_rules.dart';
import 'auth_providers.dart';
import 'repository_providers.dart';

final myEventRulesProvider =
    AsyncNotifierProvider<MyEventRulesNotifier, List<EventRulesTemplate>>(
  MyEventRulesNotifier.new,
);

class MyEventRulesNotifier extends AsyncNotifier<List<EventRulesTemplate>> {
  @override
  Future<List<EventRulesTemplate>> build() async {
    ref.watch(authStateProvider);
    final uid = ref.watch(supabaseClientProvider).auth.currentUser?.id;
    if (uid == null) return const [];
    return ref.read(eventRulesRepositoryProvider).fetchMine();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final uid = ref.read(supabaseClientProvider).auth.currentUser?.id;
      if (uid == null) return const <EventRulesTemplate>[];
      return ref.read(eventRulesRepositoryProvider).fetchMine();
    });
  }
}
