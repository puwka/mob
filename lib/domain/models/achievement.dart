abstract final class AchievementTypes {
  static const gamesPlayed = 'games_played';
  static const wins = 'wins';
  static const polygonsVisited = 'polygons_visited';
  static const rating = 'rating';
  static const eventsCount = 'events_count';
}

class Achievement {
  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.type,
    required this.requiredValue,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String description;
  final String icon;
  final String type;
  final int requiredValue;
  final DateTime createdAt;

  factory Achievement.fromJson(Map<String, dynamic> json) {
    return Achievement(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      icon: json['icon'] as String,
      type: json['type'] as String,
      requiredValue: (json['required_value'] as num).toInt(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
