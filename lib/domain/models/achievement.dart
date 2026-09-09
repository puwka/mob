abstract final class AchievementTypes {
  static const gamesPlayed = 'games_played';
  static const wins = 'wins';
  static const polygonsVisited = 'polygons_visited';
  static const rating = 'rating';
  static const eventsCount = 'events_count';
  static const teamGames = 'team_games';
  static const organizedEvents = 'organized_events';
  static const organizedParticipants = 'organized_participants';
  static const roleGames = 'role_games';
  static const messagesSent = 'messages_sent';
  static const datingLikes = 'dating_likes';
  static const profilePhotos = 'profile_photos';
  static const clanJoined = 'clan_joined';
  static const eventsAttendedConfirmed = 'events_attended_confirmed';
  static const listingsPublished = 'listings_published';
}

/// Live counters used when evaluating achievement progress.
class AchievementMetrics {
  const AchievementMetrics({
    this.gamesPlayed = 0,
    this.wins = 0,
    this.polygonsVisited = 0,
    this.rating = 0,
    this.eventsCount = 0,
    this.teamGames = 0,
    this.organizedEvents = 0,
    this.organizedParticipants = 0,
    this.roleGames = 0,
    this.messagesSent = 0,
    this.datingLikes = 0,
    this.profilePhotos = 0,
    this.clanJoined = 0,
    this.eventsAttendedConfirmed = 0,
    this.listingsPublished = 0,
  });

  final int gamesPlayed;
  final int wins;
  final int polygonsVisited;
  final int rating;
  final int eventsCount;
  final int teamGames;
  final int organizedEvents;
  final int organizedParticipants;
  final int roleGames;
  final int messagesSent;
  final int datingLikes;
  final int profilePhotos;
  final int clanJoined;
  final int eventsAttendedConfirmed;
  final int listingsPublished;

  factory AchievementMetrics.fromJson(Map<String, dynamic> json) {
    int n(String key) => (json[key] as num?)?.toInt() ?? 0;
    return AchievementMetrics(
      gamesPlayed: n('games_played'),
      wins: n('wins'),
      polygonsVisited: n('polygons_visited'),
      rating: n('rating'),
      eventsCount: n('events_count'),
      teamGames: n('team_games'),
      organizedEvents: n('organized_events'),
      organizedParticipants: n('organized_participants'),
      roleGames: n('role_games'),
      messagesSent: n('messages_sent'),
      datingLikes: n('dating_likes'),
      profilePhotos: n('profile_photos'),
      clanJoined: n('clan_joined'),
      eventsAttendedConfirmed: n('events_attended_confirmed'),
      listingsPublished: n('listings_published'),
    );
  }

  int valueFor(String type) {
    switch (type) {
      case AchievementTypes.gamesPlayed:
        return gamesPlayed;
      case AchievementTypes.wins:
        return wins;
      case AchievementTypes.polygonsVisited:
        return polygonsVisited;
      case AchievementTypes.rating:
        return rating;
      case AchievementTypes.eventsCount:
        return eventsCount;
      case AchievementTypes.teamGames:
        return teamGames;
      case AchievementTypes.organizedEvents:
        return organizedEvents;
      case AchievementTypes.organizedParticipants:
        return organizedParticipants;
      case AchievementTypes.roleGames:
        return roleGames;
      case AchievementTypes.messagesSent:
        return messagesSent;
      case AchievementTypes.datingLikes:
        return datingLikes;
      case AchievementTypes.profilePhotos:
        return profilePhotos;
      case AchievementTypes.clanJoined:
        return clanJoined;
      case AchievementTypes.eventsAttendedConfirmed:
        return eventsAttendedConfirmed;
      case AchievementTypes.listingsPublished:
        return listingsPublished;
      default:
        return 0;
    }
  }
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
