import '../domain/models/achievement.dart';
import '../domain/models/user_achievement_progress.dart';

/// Computes achievement progress from live metrics.
class AchievementService {
  const AchievementService();

  int valueForType(String type, AchievementMetrics metrics) {
    return metrics.valueFor(type);
  }

  List<UserAchievementProgress> evaluate({
    required List<Achievement> catalog,
    required AchievementMetrics metrics,
    Map<String, UserAchievementRecord> existing = const {},
  }) {
    final items = catalog.map((achievement) {
      final current = valueForType(achievement.type, metrics);
      final record = existing[achievement.id];
      final unlocked = switch (record?.adminOverride) {
        AchievementAdminOverride.revoked => false,
        AchievementAdminOverride.granted => true,
        _ =>
          (record?.unlocked ?? false) ||
              current >= achievement.requiredValue,
      };
      final capped = unlocked
          ? achievement.requiredValue
          : current.clamp(0, achievement.requiredValue);
      final ratio = achievement.requiredValue == 0
          ? 1.0
          : (capped / achievement.requiredValue).clamp(0.0, 1.0);

      return UserAchievementProgress(
        achievement: achievement,
        progress: capped,
        unlocked: unlocked,
        progressRatio: ratio.toDouble(),
        unlockedAt: unlocked
            ? (record?.unlockedAt ?? DateTime.now().toUtc())
            : record?.unlockedAt,
        userAchievementId: record?.id,
      );
    }).toList();

    // Keep awards for catalog entries that were removed / deactivated.
    final catalogIds = {for (final a in catalog) a.id};
    for (final record in existing.values) {
      if (record.adminOverride == AchievementAdminOverride.revoked) continue;
      if (!record.unlocked &&
          record.adminOverride != AchievementAdminOverride.granted) {
        continue;
      }
      if (catalogIds.contains(record.achievementId)) continue;
      final achievement = record.achievement;
      if (achievement == null) continue;
      items.add(
        UserAchievementProgress(
          achievement: achievement,
          progress: achievement.requiredValue,
          unlocked: true,
          progressRatio: 1,
          unlockedAt: record.unlockedAt,
          userAchievementId: record.id,
        ),
      );
    }

    items.sort((a, b) {
      if (a.unlocked != b.unlocked) return a.unlocked ? -1 : 1;
      return a.achievement.requiredValue.compareTo(
        b.achievement.requiredValue,
      );
    });
    return items;
  }

  AchievementVisualState visualState(UserAchievementProgress item) {
    if (item.unlocked) return AchievementVisualState.unlocked;
    if (item.progress > 0) return AchievementVisualState.progress;
    return AchievementVisualState.locked;
  }
}

enum AchievementVisualState { locked, progress, unlocked }
