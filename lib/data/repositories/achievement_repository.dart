import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/achievement.dart';
import '../../domain/models/profile.dart';
import '../../domain/models/user_achievement_progress.dart';
import '../../services/achievement_service.dart';

class AchievementSyncResult {
  const AchievementSyncResult({
    required this.items,
    required this.newlyUnlocked,
  });

  final List<UserAchievementProgress> items;
  final List<UserAchievementProgress> newlyUnlocked;
}

class AchievementRepository {
  AchievementRepository({
    required SupabaseClient client,
    AchievementService service = const AchievementService(),
  })  : _client = client,
        _service = service;

  final SupabaseClient _client;
  final AchievementService _service;

  Future<List<Achievement>> fetchCatalog() async {
    final rows = await _client
        .from('achievements')
        .select()
        .eq('is_active', true)
        .order('required_value');

    return (rows as List)
        .map((e) => Achievement.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<UserAchievementRecord>> fetchUserRecords(String userId) async {
    final rows = await _client
        .from('user_achievements')
        .select()
        .eq('user_id', userId);

    return (rows as List)
        .map(
          (e) => UserAchievementRecord.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
  }

  Future<AchievementMetrics> fetchMetrics(String userId) async {
    try {
      final raw = await _client.rpc(
        'get_achievement_metrics',
        params: {'p_user_id': userId},
      );
      if (raw is Map) {
        return AchievementMetrics.fromJson(Map<String, dynamic>.from(raw));
      }
    } catch (_) {}
    return const AchievementMetrics();
  }

  /// Recalculates progress from live metrics and upserts rows.
  Future<AchievementSyncResult> syncForProfile({
    required String userId,
    required Profile profile,
    required int eventsCount,
    List<Achievement>? catalog,
  }) async {
    final achievements = catalog ?? await fetchCatalog();
    final existingRows = await fetchUserRecords(userId);
    final existing = {
      for (final row in existingRows) row.achievementId: row,
    };

    var metrics = await fetchMetrics(userId);
    if (metrics.gamesPlayed == 0 &&
        metrics.wins == 0 &&
        metrics.rating == 0 &&
        profile.gamesPlayed + profile.wins + profile.rating > 0) {
      // RPC unavailable — fall back to profile + events count.
      metrics = AchievementMetrics(
        gamesPlayed: profile.gamesPlayed,
        wins: profile.wins,
        polygonsVisited: profile.polygonsVisited,
        rating: profile.rating,
        eventsCount: eventsCount,
        teamGames: (profile.teamName?.trim().isNotEmpty ?? false)
            ? profile.gamesPlayed
            : 0,
        roleGames: (profile.gameRole?.trim().isNotEmpty ?? false)
            ? profile.gamesPlayed
            : 0,
      );
    }

    final evaluated = _service.evaluate(
      catalog: achievements,
      metrics: metrics,
      existing: existing,
    );

    final newlyUnlocked = <UserAchievementProgress>[];
    final upserts = <Map<String, dynamic>>[];
    for (final item in evaluated) {
      final prev = existing[item.achievement.id];
      final wasUnlocked = prev?.unlocked ?? false;
      if (item.unlocked && !wasUnlocked) newlyUnlocked.add(item);

      upserts.add({
        'achievement_id': item.achievement.id,
        'progress': item.progress,
        'unlocked': item.unlocked,
      });
    }

    if (upserts.isNotEmpty) {
      await _client.rpc(
        'sync_user_achievements',
        params: {'p_items': upserts},
      );
    }

    return AchievementSyncResult(
      items: evaluated,
      newlyUnlocked: newlyUnlocked,
    );
  }

  /// Read-only progress for any user (no DB upsert).
  Future<List<UserAchievementProgress>> loadProgress({
    required Profile profile,
    required int eventsCount,
  }) async {
    final achievements = await fetchCatalog();
    final existingRows = await fetchUserRecords(profile.id);
    final existing = {
      for (final row in existingRows) row.achievementId: row,
    };
    var metrics = await fetchMetrics(profile.id);
    if (metrics.gamesPlayed == 0 &&
        metrics.eventsCount == 0 &&
        (profile.gamesPlayed > 0 || eventsCount > 0)) {
      metrics = AchievementMetrics(
        gamesPlayed: profile.gamesPlayed,
        wins: profile.wins,
        polygonsVisited: profile.polygonsVisited,
        rating: profile.rating,
        eventsCount: eventsCount,
        teamGames: (profile.teamName?.trim().isNotEmpty ?? false)
            ? profile.gamesPlayed
            : 0,
        roleGames: (profile.gameRole?.trim().isNotEmpty ?? false)
            ? profile.gamesPlayed
            : 0,
      );
    }
    return _service.evaluate(
      catalog: achievements,
      metrics: metrics,
      existing: existing,
    );
  }
}
