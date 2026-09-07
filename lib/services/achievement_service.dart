import '../domain/models/achievement.dart';
import '../domain/models/profile.dart';
import '../domain/models/user_achievement_progress.dart';

/// Computes achievement progress from profile + live events count.
class AchievementService {
  const AchievementService();

  int valueForType(
    Profile profile,
    String type, {
    required int eventsCount,
  }) {
    switch (type) {
      case AchievementTypes.gamesPlayed:
        return profile.gamesPlayed;
      case AchievementTypes.wins:
        return profile.wins;
      case AchievementTypes.polygonsVisited:
        return profile.polygonsVisited;
      case AchievementTypes.rating:
        return profile.rating;
      case AchievementTypes.eventsCount:
        return eventsCount;
      default:
        return 0;
    }
  }

  List<UserAchievementProgress> evaluate({
    required Profile profile,
    required List<Achievement> catalog,
    required int eventsCount,
    Map<String, UserAchievementRecord> existing = const {},
  }) {
    return catalog.map((achievement) {
      final current = valueForType(
        profile,
        achievement.type,
        eventsCount: eventsCount,
      );
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
