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
    return catalog.map((achievement) {
      final current = valueForType(achievement.type, metrics);
      final capped = current.clamp(0, achievement.requiredValue);
      final unlocked = current >= achievement.requiredValue;
      final ratio = achievement.requiredValue == 0
          ? 1.0
          : (current / achievement.requiredValue).clamp(0.0, 1.0);

      final record = existing[achievement.id];

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
    }).toList()
      ..sort((a, b) {
        if (a.unlocked != b.unlocked) return a.unlocked ? -1 : 1;
        return a.achievement.requiredValue.compareTo(
          b.achievement.requiredValue,
        );
      });
  }

  AchievementVisualState visualState(UserAchievementProgress item) {
    if (item.unlocked) return AchievementVisualState.unlocked;
    if (item.progress > 0) return AchievementVisualState.progress;
    return AchievementVisualState.locked;
  }
}

enum AchievementVisualState { locked, progress, unlocked }
