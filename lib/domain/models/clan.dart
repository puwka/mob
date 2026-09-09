enum ClanRole {
  leader,
  officer,
  trainer,
  member;

  static ClanRole fromString(String value) {
    return switch (value) {
      'leader' || 'owner' => ClanRole.leader,
      'officer' || 'deputy' => ClanRole.officer,
      'trainer' => ClanRole.trainer,
      _ => ClanRole.member,
    };
  }

  String get dbValue => name;

  String get labelRu => switch (this) {
        ClanRole.leader => 'Командир',
        ClanRole.officer => 'Заместитель командира',
        ClanRole.trainer => 'Тренер',
        ClanRole.member => 'Боец',
      };

  bool get isLeadership =>
      this == ClanRole.leader ||
      this == ClanRole.officer ||
      this == ClanRole.trainer;

  bool get canKickMembers =>
      this == ClanRole.leader || this == ClanRole.officer;

  bool get canAssignRoles => this == ClanRole.leader;
}

enum ClanJoinStatus {
  pending,
  approved,
  rejected;

  static ClanJoinStatus fromString(String value) {
    return ClanJoinStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ClanJoinStatus.pending,
    );
  }
}

class Clan {
  const Clan({
    required this.id,
    required this.name,
    required this.tag,
    required this.description,
    this.city,
    this.avatarUrl,
    this.leaderId,
    this.leaderNickname,
    required this.rating,
    required this.membersCount,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String tag;
  final String description;
  final String? city;
  final String? avatarUrl;
  final String? leaderId;
  final String? leaderNickname;
  final int rating;
  final int membersCount;
  final DateTime createdAt;

  String get displayTag => '[$tag]';

  String get ratingLabel => rating.toString();

  factory Clan.fromJson(Map<String, dynamic> json) {
    return Clan(
      id: json['id'] as String,
      name: json['name'] as String,
      tag: (json['tag'] as String? ?? '').toUpperCase(),
      description: json['description'] as String? ?? '',
      city: (json['city'] as String?)?.trim(),
      avatarUrl: json['avatar_url'] as String?,
      leaderId: json['leader_id'] as String?,
      leaderNickname: json['leader_nickname'] as String?,
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      membersCount: (json['members_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(
        json['created_at'] as String? ?? DateTime.now().toIso8601String(),
      ),
    );
  }
}

class ClanMember {
  const ClanMember({
    required this.clanId,
    required this.userId,
    required this.role,
    required this.joinedAt,
    required this.nickname,
    required this.rating,
    this.avatarUrl,
  });

  final String clanId;
  final String userId;
  final ClanRole role;
  final DateTime joinedAt;
  final String nickname;
  final int rating;
  final String? avatarUrl;

  factory ClanMember.fromJson(Map<String, dynamic> json) {
    String nickname = 'Боец';
    int rating = 0;
    String? avatar;
    final profile = json['profile'] ?? json['profiles'];
    if (profile is Map) {
      nickname = profile['nickname'] as String? ?? nickname;
      rating = (profile['rating'] as num?)?.toInt() ?? 0;
      avatar = profile['avatar_url'] as String?;
    } else {
      nickname = json['nickname'] as String? ?? nickname;
      rating = (json['rating'] as num?)?.toInt() ?? 0;
      avatar = json['avatar_url'] as String?;
    }

    return ClanMember(
      clanId: json['clan_id'] as String,
      userId: json['user_id'] as String,
      role: ClanRole.fromString(json['role'] as String? ?? 'member'),
      joinedAt: DateTime.parse(
        json['joined_at'] as String? ?? DateTime.now().toIso8601String(),
      ),
      nickname: nickname,
      rating: rating,
      avatarUrl: avatar,
    );
  }
}

class ClanJoinRequest {
  const ClanJoinRequest({
    required this.id,
    required this.clanId,
    required this.userId,
    required this.status,
    required this.createdAt,
    this.nickname,
    this.avatarUrl,
    this.rating = 0,
    this.clanName,
    this.clanTag,
  });

  final String id;
  final String clanId;
  final String userId;
  final ClanJoinStatus status;
  final DateTime createdAt;
  final String? nickname;
  final String? avatarUrl;
  final int rating;
  final String? clanName;
  final String? clanTag;

  factory ClanJoinRequest.fromJson(Map<String, dynamic> json) {
    String? nick;
    String? avatar;
    var rating = 0;
    final profile = json['profile'] ?? json['profiles'];
    if (profile is Map) {
      nick = profile['nickname'] as String?;
      avatar = profile['avatar_url'] as String?;
      rating = (profile['rating'] as num?)?.toInt() ?? 0;
    }

    String? clanName;
    String? clanTag;
    final clan = json['clan'] ?? json['clans'];
    if (clan is Map) {
      clanName = clan['name'] as String?;
      clanTag = clan['tag'] as String?;
    }

    return ClanJoinRequest(
      id: json['id'] as String,
      clanId: json['clan_id'] as String,
      userId: json['user_id'] as String,
      status: ClanJoinStatus.fromString(json['status'] as String? ?? 'pending'),
      createdAt: DateTime.parse(json['created_at'] as String),
      nickname: nick,
      avatarUrl: avatar,
      rating: rating,
      clanName: clanName,
      clanTag: clanTag,
    );
  }
}
