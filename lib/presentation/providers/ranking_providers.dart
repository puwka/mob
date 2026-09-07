import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/ranking_repository.dart';
import '../../domain/models/ranking.dart';
import 'auth_providers.dart';
import 'repository_providers.dart';

final rankingEntityTabProvider =
    StateProvider<RankingEntityTab>((ref) => RankingEntityTab.players);

final rankingScopeTabProvider =
    StateProvider<RankingScopeTab>((ref) => RankingScopeTab.regional);

/// When true, sticky "you" card is emphasized (opened from profile rating).
final rankingHighlightMeProvider = StateProvider<bool>((ref) => false);

/// Effective city filter: null = global; regional uses current profile city.
final rankingCityFilterProvider = Provider<String?>((ref) {
  final scope = ref.watch(rankingScopeTabProvider);
  if (scope == RankingScopeTab.global) return null;
  return ref.watch(currentProfileProvider).valueOrNull?.city;
});

class RankingPlayersState {
  const RankingPlayersState({
    required this.items,
    required this.hasMore,
    this.myEntry,
  });

  final List<RankingPlayerEntry> items;
  final bool hasMore;
  final RankingPlayerEntry? myEntry;

  List<RankingPlayerEntry> get top3 =>
      items.where((e) => e.rank <= 3).take(3).toList();

  List<RankingPlayerEntry> get listFrom4 =>
      items.where((e) => e.rank > 3).toList();
}

class RankingClansState {
  const RankingClansState({
    required this.items,
    required this.hasMore,
    this.myEntry,
  });

  final List<RankingClanEntry> items;
  final bool hasMore;
  final RankingClanEntry? myEntry;

  List<RankingClanEntry> get top3 =>
      items.where((e) => e.rank <= 3).take(3).toList();

  List<RankingClanEntry> get listFrom4 =>
      items.where((e) => e.rank > 3).toList();
}

final rankingPlayersProvider =
    AsyncNotifierProvider<RankingPlayersNotifier, RankingPlayersState>(
  RankingPlayersNotifier.new,
);

class RankingPlayersNotifier extends AsyncNotifier<RankingPlayersState> {
  @override
  Future<RankingPlayersState> build() async {
    final city = ref.watch(rankingCityFilterProvider);
    return _load(city: city, offset: 0, append: false);
  }

  Future<RankingPlayersState> _load({
    required String? city,
    required int offset,
    required bool append,
  }) async {
    final repo = ref.read(rankingRepositoryProvider);
    final page = await repo.fetchPlayers(city: city, offset: offset);
    final mine = await repo.fetchMyPlayerRank(city: city);

    final prev = append ? (state.valueOrNull?.items ?? const []) : const [];
    final merged = [...prev, ...page];
    // Dedupe by id keeping first (stable ranks)
    final seen = <String>{};
    final items = <RankingPlayerEntry>[];
    for (final e in merged) {
      if (seen.add(e.id)) items.add(e);
    }

    return RankingPlayersState(
      items: items,
      hasMore: page.length >= RankingRepository.pageSize,
      myEntry: mine,
    );
  }

  Future<void> refresh() async {
    final city = ref.read(rankingCityFilterProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _load(city: city, offset: 0, append: false),
    );
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore) return;
    final city = ref.read(rankingCityFilterProvider);
    final next = await AsyncValue.guard(
      () => _load(city: city, offset: current.items.length, append: true),
    );
    if (next.hasValue) state = next;
  }
}

final rankingClansProvider =
    AsyncNotifierProvider<RankingClansNotifier, RankingClansState>(
  RankingClansNotifier.new,
);

class RankingClansNotifier extends AsyncNotifier<RankingClansState> {
  @override
  Future<RankingClansState> build() async {
    final city = ref.watch(rankingCityFilterProvider);
    return _load(city: city, offset: 0, append: false);
  }

  Future<RankingClansState> _load({
    required String? city,
    required int offset,
    required bool append,
  }) async {
    final repo = ref.read(rankingRepositoryProvider);
    final page = await repo.fetchClans(city: city, offset: offset);
    final mine = await repo.fetchMyClanRank(city: city);

    final prev = append ? (state.valueOrNull?.items ?? const []) : const [];
    final merged = [...prev, ...page];
    final seen = <String>{};
    final items = <RankingClanEntry>[];
    for (final e in merged) {
      if (seen.add(e.id)) items.add(e);
    }

    return RankingClansState(
      items: items,
      hasMore: page.length >= RankingRepository.pageSize,
      myEntry: mine,
    );
  }

  Future<void> refresh() async {
    final city = ref.read(rankingCityFilterProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _load(city: city, offset: 0, append: false),
    );
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore) return;
    final city = ref.read(rankingCityFilterProvider);
    final next = await AsyncValue.guard(
      () => _load(city: city, offset: current.items.length, append: true),
    );
    if (next.hasValue) state = next;
  }
}
