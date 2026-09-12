import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/clan.dart';
import 'auth_providers.dart';
import 'repository_providers.dart';

final myClanProvider = AsyncNotifierProvider<MyClanNotifier, Clan?>(
  MyClanNotifier.new,
);

class MyClanNotifier extends AsyncNotifier<Clan?> {
  @override
  Future<Clan?> build() {
    ref.watch(authStateProvider);
    final userId = ref.watch(supabaseClientProvider).auth.currentUser?.id;
    if (userId == null) return Future.value(null);
    return ref.read(clanRepositoryProvider).fetchClanForUser(userId);
  }

  Future<void> refresh({bool silent = false}) async {
    if (!silent) state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
      if (userId == null) return null;
      return ref.read(clanRepositoryProvider).fetchClanForUser(userId);
    });
  }
}

final clanForUserProvider = FutureProvider.family<Clan?, String>((ref, userId) {
  return ref.watch(clanRepositoryProvider).fetchClanForUser(userId);
});

final clanDetailProvider =
    AsyncNotifierProvider.family<ClanDetailNotifier, Clan, String>(
  ClanDetailNotifier.new,
);

class ClanDetailNotifier extends FamilyAsyncNotifier<Clan, String> {
  @override
  Future<Clan> build(String arg) {
    return ref.read(clanRepositoryProvider).fetchClan(arg);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(clanRepositoryProvider).fetchClan(arg),
    );
  }

  void apply(Clan clan) {
    state = AsyncData(clan);
  }
}

final clanMembersProvider =
    FutureProvider.family<List<ClanMember>, String>((ref, clanId) {
  return ref.watch(clanRepositoryProvider).fetchMembers(clanId);
});

final clanSearchQueryProvider = StateProvider<String>((ref) => '');

/// Clan directory: only clans from the current user's profile city.
/// All-city clans live in Ranking (Общий).
final clanSearchProvider = FutureProvider<List<Clan>>((ref) {
  final q = ref.watch(clanSearchQueryProvider);
  final city = ref.watch(currentProfileProvider).valueOrNull?.city;
  return ref.watch(clanRepositoryProvider).searchClans(query: q, city: city);
});

final clanPendingRequestsProvider =
    FutureProvider.family<List<ClanJoinRequest>, String>((ref, clanId) {
  return ref.watch(clanRepositoryProvider).fetchPendingRequests(clanId);
});

final myClanRoleProvider =
    FutureProvider.family<ClanRole?, String>((ref, clanId) {
  return ref.watch(clanRepositoryProvider).myRoleIn(clanId);
});

final myJoinStatusProvider =
    FutureProvider.family<ClanJoinStatus?, String>((ref, clanId) {
  return ref.watch(clanRepositoryProvider).myRequestStatus(clanId);
});
