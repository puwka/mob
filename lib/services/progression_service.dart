import '../domain/models/profile.dart';
import '../domain/models/user_achievement_progress.dart';
import 'level_service.dart';

/// Result of rebuilding XP / level / achievements from live data.
class ProgressionSnapshot {
  const ProgressionSnapshot({
    required this.eventsCount,
    required this.level,
    required this.achievements,
    required this.newlyUnlocked,
    this.previousLevel,
  });

  final int eventsCount;
  final LevelProgress level;
  final List<UserAchievementProgress> achievements;
  final List<UserAchievementProgress> newlyUnlocked;
  final int? previousLevel;

  bool get leveledUp =>
      previousLevel != null && level.currentLevel > previousLevel!;
}

/// Builds progression snapshots (no Supabase / no UI).
class ProgressionService {
  const ProgressionService({
    this.levelService = const LevelService(),
  });

  final LevelService levelService;

  ProgressionSnapshot buildSnapshot({
    required Profile profile,
    required int eventsCount,
    required List<UserAchievementProgress> achievements,
    required List<UserAchievementProgress> newlyUnlocked,
    int? previousLevel,
  }) {
    return ProgressionSnapshot(
      eventsCount: eventsCount,
      level: levelService.calculateFromProfile(
        profile,
        eventsCount: eventsCount,
      ),
      achievements: achievements,
      newlyUnlocked: newlyUnlocked,
      previousLevel: previousLevel,
    );
  }
}
