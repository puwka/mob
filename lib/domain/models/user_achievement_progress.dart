import 'achievement.dart';

/// Row from `user_achievements`.
class UserAchievementRecord {
  const UserAchievementRecord({
    required this.id,
    required this.userId,
    required this.achievementId,
    required this.progress,
    required this.unlocked,
    this.unlockedAt,
  });

  final String id;
  final String userId;
  final String achievementId;
  final int progress;
  final bool unlocked;
  final DateTime? unlockedAt;

  factory UserAchievementRecord.fromJson(Map<String, dynamic> json) {
    return UserAchievementRecord(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      achievementId: json['achievement_id'] as String,
      progress: (json['progress'] as num?)?.toInt() ?? 0,
      unlocked: json['unlocked'] as bool? ?? false,
      unlockedAt: json['unlocked_at'] == null
          ? null
          : DateTime.parse(json['unlocked_at'] as String),
    );
  }

  Map<String, dynamic> toUpsertJson() {
    return {
      'user_id': userId,
      'achievement_id': achievementId,
      'progress': progress,
      'unlocked': unlocked,
      'unlocked_at': unlockedAt?.toIso8601String(),
    };
  }
}

/// Combined catalog + user progress for UI.
class UserAchievementProgress {
  const UserAchievementProgress({
    required this.achievement,
    required this.progress,
    required this.unlocked,
    required this.progressRatio,
    this.unlockedAt,
    this.userAchievementId,
  });

  final Achievement achievement;
  final int progress;
  final bool unlocked;
  final double progressRatio;
  final DateTime? unlockedAt;
  final String? userAchievementId;
}
