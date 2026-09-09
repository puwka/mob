enum DatingActionType {
  like,
  skip;

  String get dbValue => name;

  static DatingActionType fromString(String? value) {
    switch (value) {
      case 'skip':
        return DatingActionType.skip;
      case 'like':
      default:
        return DatingActionType.like;
    }
  }
}

/// Public dating profile fields only (no phone / QR / balance / roles).
class DatingPublicUser {
  const DatingPublicUser({
    required this.id,
    required this.nickname,
    required this.city,
    this.avatarUrl,
  });

  final String id;
  final String nickname;
  final String city;
  final String? avatarUrl;

  factory DatingPublicUser.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const DatingPublicUser(id: '', nickname: '', city: '');
    }
    return DatingPublicUser(
      id: json['id'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '',
      city: json['city'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}

class DatingCandidate {
  const DatingCandidate({
    required this.id,
    required this.nickname,
    required this.city,
    this.avatarUrl,
    required this.photoUrls,
    this.age,
    this.gender,
    this.about,
  });

  final String id;
  final String nickname;
  final String city;
  final String? avatarUrl;
  final List<String> photoUrls;
  final int? age;
  final String? gender;
  final String? about;

  /// Avatar first, then gallery — already ordered by the feed RPC (max 5).
  List<String> get displayPhotos {
    if (photoUrls.isNotEmpty) return photoUrls;
    final avatar = avatarUrl?.trim();
    if (avatar != null && avatar.isNotEmpty) return [avatar];
    return const [];
  }

  factory DatingCandidate.fromJson(Map<String, dynamic> json) {
    final rawPhotos = json['photo_urls'];
    final photos = <String>[];
    if (rawPhotos is List) {
      for (final item in rawPhotos) {
        final url = '$item'.trim();
        if (url.isNotEmpty) photos.add(url);
      }
    }

    return DatingCandidate(
      id: json['id'] as String,
      nickname: json['nickname'] as String? ?? '',
      city: json['city'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      photoUrls: photos.take(5).toList(),
      age: (json['age'] as num?)?.toInt(),
      gender: json['gender'] as String?,
      about: json['about'] as String?,
    );
  }
}

class DatingActionResult {
  const DatingActionResult({
    required this.actionId,
    required this.toUserId,
    required this.action,
    required this.matched,
    required this.inserted,
    required this.createdAt,
    this.matchId,
    this.conversationId,
    required this.me,
    required this.target,
  });

  final String actionId;
  final String toUserId;
  final DatingActionType action;
  final bool matched;
  final bool inserted;
  final DateTime createdAt;
  final String? matchId;
  final String? conversationId;
  final DatingPublicUser me;
  final DatingPublicUser target;

  bool get shouldShowMatchUi =>
      matched && inserted && matchId != null && matchId!.isNotEmpty;

  factory DatingActionResult.fromJson(Map<String, dynamic> json) {
    final meRaw = json['me'];
    final targetRaw = json['target'];
    final createdRaw = json['created_at'];
    DateTime createdAt;
    if (createdRaw is DateTime) {
      createdAt = createdRaw;
    } else if (createdRaw != null) {
      createdAt = DateTime.tryParse('$createdRaw') ?? DateTime.now();
    } else {
      createdAt = DateTime.now();
    }

    String? asId(dynamic value) {
      if (value == null) return null;
      final s = '$value'.trim();
      return s.isEmpty || s == 'null' ? null : s;
    }

    return DatingActionResult(
      actionId: asId(json['action_id'] ?? json['id']) ?? '',
      toUserId: asId(json['to_user_id']) ?? '',
      action: DatingActionType.fromString(json['action'] as String?),
      matched: json['matched'] == true,
      inserted: json['inserted'] == true,
      createdAt: createdAt,
      matchId: asId(json['match_id']),
      conversationId: asId(json['conversation_id']),
      me: DatingPublicUser.fromJson(
        meRaw is Map ? Map<String, dynamic>.from(meRaw) : null,
      ),
      target: DatingPublicUser.fromJson(
        targetRaw is Map ? Map<String, dynamic>.from(targetRaw) : null,
      ),
    );
  }
}

class DatingMatch {
  const DatingMatch({
    required this.matchId,
    required this.userId,
    required this.nickname,
    required this.city,
    this.avatarUrl,
    required this.createdAt,
    this.conversationId,
  });

  final String matchId;
  final String userId;
  final String nickname;
  final String city;
  final String? avatarUrl;
  final DateTime createdAt;
  final String? conversationId;

  factory DatingMatch.fromJson(Map<String, dynamic> json) {
    return DatingMatch(
      matchId: json['match_id'] as String,
      userId: json['user_id'] as String,
      nickname: json['nickname'] as String? ?? '',
      city: json['city'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      conversationId: json['conversation_id'] as String?,
    );
  }
}

enum DatingNotificationKind {
  like,
  match;

  static DatingNotificationKind fromString(String? value) {
    switch (value) {
      case 'match':
        return DatingNotificationKind.match;
      case 'like':
      default:
        return DatingNotificationKind.like;
    }
  }
}

class DatingNotification {
  const DatingNotification({
    required this.notificationId,
    required this.kind,
    this.matchId,
    this.conversationId,
    required this.createdAt,
    required this.me,
    required this.other,
  });

  final String notificationId;
  final DatingNotificationKind kind;
  final String? matchId;
  final String? conversationId;
  final DateTime createdAt;
  final DatingPublicUser me;
  final DatingPublicUser other;

  bool get isMatch => kind == DatingNotificationKind.match;
  bool get isLike => kind == DatingNotificationKind.like;

  factory DatingNotification.fromJson(Map<String, dynamic> json) {
    final meRaw = json['me'];
    final otherRaw = json['other'];
    String? asId(dynamic value) {
      if (value == null) return null;
      final s = '$value'.trim();
      return s.isEmpty || s == 'null' ? null : s;
    }

    return DatingNotification(
      notificationId: asId(json['notification_id']) ?? '',
      kind: DatingNotificationKind.fromString(json['kind'] as String?),
      matchId: asId(json['match_id']),
      conversationId: asId(json['conversation_id']),
      createdAt: DateTime.tryParse('${json['created_at']}') ?? DateTime.now(),
      me: DatingPublicUser.fromJson(
        meRaw is Map ? Map<String, dynamic>.from(meRaw) : null,
      ),
      other: DatingPublicUser.fromJson(
        otherRaw is Map ? Map<String, dynamic>.from(otherRaw) : null,
      ),
    );
  }
}

/// Backward-compatible alias.
typedef DatingMatchNotification = DatingNotification;
