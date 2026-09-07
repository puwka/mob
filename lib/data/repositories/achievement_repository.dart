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

  /// Recalculates progress from profile + events count and upserts rows.
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

    final evaluated = _service.evaluate(
      profile: profile,
      catalog: achievements,
      eventsCount: eventsCount,
      existing: existing,
    );

    final newlyUnlocked = <UserAchievementProgress>[];

    final upserts = <Map<String, dynamic>>[];
    for (final item in evaluated) {
      final prev = existing[item.achievement.id];
      final wasUnlocked = prev?.unlocked ?? false;
      final newly = item.unlocked && !wasUnlocked;
      if (newly) newlyUnlocked.add(item);

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
}
