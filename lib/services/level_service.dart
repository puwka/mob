import '../domain/models/profile.dart';

/// Progressive level progression derived from total XP.
class LevelProgress {
  const LevelProgress({
    required this.currentXp,
    required this.currentLevel,
    required this.xpIntoLevel,
    required this.xpForNextLevel,
    required this.nextLevelXp,
    required this.progress,
  });

  final int currentXp;
  final int currentLevel;
  final int xpIntoLevel;
  final int xpForNextLevel;
  final int nextLevelXp;
  final double progress;
}

/// Central XP formula — keep out of widgets.
/// Must stay in sync with SQL `public.compute_player_xp`.
class XpService {
  const XpService();

  /// XP =
  ///   games_played * 100
  /// + wins * 250
  /// + polygons_visited * 100
  /// + events_count * 100
  /// + bonus_xp (admin)
  ///
  /// Stored as `profiles.rating` for leaderboards;
  /// clan rating = SUM(member XP).
  int calculate({
    required int gamesPlayed,
    required int wins,
    required int polygonsVisited,
    required int eventsCount,
    int bonusXp = 0,
  }) {
    final xp = gamesPlayed * 100 +
        wins * 250 +
        polygonsVisited * 100 +
        eventsCount * 100 +
        bonusXp;
    return xp < 0 ? 0 : xp;
  }

  int calculateFromProfile(Profile profile, {required int eventsCount}) {
    final computed = calculate(
      gamesPlayed: profile.gamesPlayed,
      wins: profile.wins,
      polygonsVisited: profile.polygonsVisited,
      eventsCount: eventsCount,
      bonusXp: profile.bonusXp,
    );
    // `profiles.rating` is the synced total (activity + admin bonus). Prefer
    // it when higher so admin XP raises level even if bonus_xp isn't loaded yet.
    return profile.rating > computed ? profile.rating : computed;
  }
}

/// Maps XP → level curve.
class LevelService {
  const LevelService({this.xpService = const XpService()});

  final XpService xpService;

  int calculateXp({
    required int gamesPlayed,
    required int wins,
    required int polygonsVisited,
    required int eventsCount,
    int bonusXp = 0,
  }) {
    return xpService.calculate(
      gamesPlayed: gamesPlayed,
      wins: wins,
      polygonsVisited: polygonsVisited,
      eventsCount: eventsCount,
      bonusXp: bonusXp,
    );
  }

  /// Minimum player level required to create a clan.
  static const minLevelToCreateClan = 3;

  int xpRequiredForLevel(int level) {
    if (level < 1) return 200;
    return 200 + (level - 1) * 75;
  }

  int totalXpForLevel(int level) {
    if (level <= 1) return 0;
    var total = 0;
    for (var l = 1; l < level; l++) {
      total += xpRequiredForLevel(l);
    }
    return total;
  }

  LevelProgress calculateLevel(int xp) {
    final safeXp = xp < 0 ? 0 : xp;

    var level = 1;
    var threshold = 0;
    var nextCost = xpRequiredForLevel(1);

    while (safeXp >= threshold + nextCost) {
      threshold += nextCost;
      level++;
      nextCost = xpRequiredForLevel(level);
    }

    final intoLevel = safeXp - threshold;
    final progress =
        nextCost == 0 ? 1.0 : (intoLevel / nextCost).clamp(0.0, 1.0);

    return LevelProgress(
      currentXp: safeXp,
      currentLevel: level,
      xpIntoLevel: intoLevel,
      xpForNextLevel: nextCost,
      nextLevelXp: threshold + nextCost,
      progress: progress,
    );
  }

  LevelProgress calculateFromStats({
    required int gamesPlayed,
    required int wins,
    required int polygonsVisited,
    required int eventsCount,
    int bonusXp = 0,
  }) {
    final xp = calculateXp(
      gamesPlayed: gamesPlayed,
      wins: wins,
      polygonsVisited: polygonsVisited,
      eventsCount: eventsCount,
      bonusXp: bonusXp,
    );
    return calculateLevel(xp);
  }

  LevelProgress calculateFromProfile(
    Profile profile, {
    required int eventsCount,
  }) {
    return calculateLevel(
      xpService.calculateFromProfile(profile, eventsCount: eventsCount),
    );
  }
}
