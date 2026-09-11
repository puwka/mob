enum AppRole {
  user,
  organizer;

  static AppRole fromString(String? value) {
    switch (value) {
      case 'organizer':
        return AppRole.organizer;
      case 'user':
      default:
        return AppRole.user;
    }
  }

  String get dbValue => name;

  bool get isOrganizer => this == AppRole.organizer;
}

/// Badge near nickname: admin > moderator > organizer > sherpa > user.
enum ProfileBadgeRole {
  admin,
  moderator,
  organizer,
  sherpa,
  user;

  static ProfileBadgeRole fromString(String? value) {
    switch (value) {
      case 'admin':
        return ProfileBadgeRole.admin;
      case 'moderator':
        return ProfileBadgeRole.moderator;
      case 'organizer':
        return ProfileBadgeRole.organizer;
      case 'sherpa':
        return ProfileBadgeRole.sherpa;
      default:
        return ProfileBadgeRole.user;
    }
  }

  static ProfileBadgeRole fromAppRole(AppRole role) {
    return role.isOrganizer
        ? ProfileBadgeRole.organizer
        : ProfileBadgeRole.user;
  }

  String get labelRu => switch (this) {
        ProfileBadgeRole.admin => 'Админ',
        ProfileBadgeRole.moderator => 'Модератор',
        ProfileBadgeRole.organizer => 'Организатор',
        ProfileBadgeRole.sherpa => 'Шерп',
        ProfileBadgeRole.user => 'Пользователь',
      };

  /// Status badges worth showing next to the nickname.
  bool get isPrivileged => this != ProfileBadgeRole.user;
}

/// In-game combat role selected in profile editing (`profiles.game_role`).
enum GameRole {
  assault,
  sniper,
  medic,
  recon,
  support,
  marksman,
  grenadier;

  static const dbValues = {
    'assault',
    'sniper',
    'medic',
    'recon',
    'support',
    'marksman',
    'grenadier',
  };

  static GameRole? tryParse(String? value) {
    if (value == null) return null;
    final v = value.trim().toLowerCase();
    if (v.isEmpty) return null;
    return switch (v) {
      'assault' || 'штурмовик' || 'штурм' => GameRole.assault,
      'sniper' || 'снайпер' => GameRole.sniper,
      'medic' || 'медик' => GameRole.medic,
      'recon' || 'разведчик' || 'разведка' => GameRole.recon,
      'support' || 'пулемётчик' || 'пулеметчик' || 'поддержка' =>
        GameRole.support,
      'marksman' || 'марксман' || 'dmr' => GameRole.marksman,
      'grenadier' || 'гренадер' || 'подрывник' => GameRole.grenadier,
      _ => null,
    };
  }

  static GameRole fromString(String? value) =>
      tryParse(value) ?? GameRole.assault;

  String get dbValue => name;

  String get labelRu => switch (this) {
        GameRole.assault => 'Штурмовик',
        GameRole.sniper => 'Снайпер',
        GameRole.medic => 'Медик',
        GameRole.recon => 'Разведчик',
        GameRole.support => 'Пулемётчик',
        GameRole.marksman => 'Марксман',
        GameRole.grenadier => 'Гренадер',
      };
}

class Profile {
  const Profile({
    required this.id,
    required this.phone,
    required this.nickname,
    required this.city,
    this.avatarUrl,
    this.bio,
    this.gameRole,
    this.teamName,
    this.appRole = AppRole.user,
    this.badgeRole = ProfileBadgeRole.user,
    this.publicQrId,
    this.gamesPlayed = 0,
    this.wins = 0,
    this.rating = 0,
    this.bonusXp = 0,
    this.polygonsVisited = 0,
    this.lastSeenAt,
    required this.createdAt,
  });

  final String id;
  final String phone;
  final String nickname;
  final String city;
  final String? avatarUrl;
  final String? bio;
  /// In-game loadout label (was historically `role`).
  final String? gameRole;
  final String? teamName;
  final AppRole appRole;
  final ProfileBadgeRole badgeRole;
  final String? publicQrId;
  final int gamesPlayed;
  final int wins;
  final int rating;
  /// Admin XP adjustment; total XP = activity formula + bonusXp.
  final int bonusXp;
  final int polygonsVisited;
  final DateTime? lastSeenAt;
  final DateTime createdAt;

  bool get isOrganizer => appRole.isOrganizer;

  GameRole? get parsedGameRole => GameRole.tryParse(gameRole);

  String get gameRoleLabel {
    final parsed = parsedGameRole;
    if (parsed != null) return parsed.labelRu;
    final raw = gameRole?.trim();
    if (raw != null && raw.isNotEmpty) return raw;
    return 'Не указан';
  }

  /// Short public id for UI (first 8 of public_qr_id).
  String get shortQrLabel {
    final id = publicQrId;
    if (id == null || id.isEmpty) return '—';
    return id.replaceAll('-', '').substring(0, 8).toUpperCase();
  }

  /// Payload encoded into QR — public token only.
  String get qrPayload {
    final token = publicQrId;
    if (token == null || token.isEmpty) return '';
    return 'tactical:qr:$token';
  }

  factory Profile.fromJson(Map<String, dynamic> json) {
    // Support both legacy `role` as game role and new app `role`.
    final appRoleRaw = json['role'] as String?;
    final gameRoleRaw = (json['game_role'] as String?) ??
        (appRoleRaw != null &&
                appRoleRaw != 'user' &&
                appRoleRaw != 'organizer'
            ? appRoleRaw
            : null);

    final appRole = AppRole.fromString(
      appRoleRaw == 'user' || appRoleRaw == 'organizer' ? appRoleRaw : 'user',
    );
    final badgeRaw = json['badge_role'] as String?;

    return Profile(
      id: json['id'] as String,
      phone: json['phone'] as String? ?? '',
      nickname: json['nickname'] as String,
      city: json['city'] as String,
      avatarUrl: json['avatar_url'] as String?,
      bio: json['bio'] as String?,
      gameRole: gameRoleRaw,
      teamName: json['team_name'] as String?,
      appRole: appRole,
      badgeRole: badgeRaw != null
          ? ProfileBadgeRole.fromString(badgeRaw)
          : ProfileBadgeRole.fromAppRole(appRole),
      publicQrId: json['public_qr_id'] as String?,
      gamesPlayed: (json['games_played'] as num?)?.toInt() ?? 0,
      wins: (json['wins'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      bonusXp: (json['bonus_xp'] as num?)?.toInt() ?? 0,
      polygonsVisited: (json['polygons_visited'] as num?)?.toInt() ?? 0,
      lastSeenAt: json['last_seen_at'] == null
          ? null
          : DateTime.parse(json['last_seen_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'id': id,
      'phone': phone,
      'nickname': nickname,
      'city': city,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (bio != null) 'bio': bio,
      if (gameRole != null) 'game_role': gameRole,
      if (teamName != null) 'team_name': teamName,
      // role + public_qr_id set by DB defaults / triggers — never client-elevate
      'games_played': gamesPlayed,
      'wins': wins,
      'rating': rating,
      'polygons_visited': polygonsVisited,
    };
  }

  Profile copyWith({
    String? nickname,
    String? city,
    String? avatarUrl,
    bool clearAvatarUrl = false,
    String? bio,
    bool clearBio = false,
    String? gameRole,
    String? teamName,
    AppRole? appRole,
    ProfileBadgeRole? badgeRole,
    String? publicQrId,
    int? gamesPlayed,
    int? wins,
    int? rating,
    int? bonusXp,
    int? polygonsVisited,
    DateTime? lastSeenAt,
  }) {
    return Profile(
      id: id,
      phone: phone,
      nickname: nickname ?? this.nickname,
      city: city ?? this.city,
      avatarUrl: clearAvatarUrl ? null : (avatarUrl ?? this.avatarUrl),
      bio: clearBio ? null : (bio ?? this.bio),
      gameRole: gameRole ?? this.gameRole,
      teamName: teamName ?? this.teamName,
      appRole: appRole ?? this.appRole,
      badgeRole: badgeRole ?? this.badgeRole,
      publicQrId: publicQrId ?? this.publicQrId,
      gamesPlayed: gamesPlayed ?? this.gamesPlayed,
      wins: wins ?? this.wins,
      rating: rating ?? this.rating,
      bonusXp: bonusXp ?? this.bonusXp,
      polygonsVisited: polygonsVisited ?? this.polygonsVisited,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      createdAt: createdAt,
    );
  }
}
