enum EventStatus {
  draft,
  active,
  finished,
  cancelled;

  static EventStatus fromString(String? value) {
    switch (value) {
      case 'draft':
        return EventStatus.draft;
      case 'finished':
        return EventStatus.finished;
      case 'cancelled':
        return EventStatus.cancelled;
      case 'active':
      default:
        return EventStatus.active;
    }
  }

  String get dbValue => name;

  String get labelRu => switch (this) {
        EventStatus.draft => 'Черновик',
        EventStatus.active => 'Активно',
        EventStatus.finished => 'Завершено',
        EventStatus.cancelled => 'Отменено',
      };
}

enum RegistrationStatus {
  registered,
  cancelled;

  static RegistrationStatus fromString(String? value) {
    return value == 'cancelled'
        ? RegistrationStatus.cancelled
        : RegistrationStatus.registered;
  }
}

enum AttendanceStatus {
  notConfirmed,
  confirmed;

  static AttendanceStatus fromString(String? value) {
    return value == 'confirmed'
        ? AttendanceStatus.confirmed
        : AttendanceStatus.notConfirmed;
  }

  String get labelRu => switch (this) {
        AttendanceStatus.confirmed => 'Присутствует',
        AttendanceStatus.notConfirmed => 'Не подтвержден',
      };
}

enum EventSide {
  light,
  dark;

  static EventSide? fromString(String? value) {
    switch (value) {
      case 'light':
        return EventSide.light;
      case 'dark':
        return EventSide.dark;
      default:
        return null;
    }
  }

  String get dbValue => name;

  String get labelRu => switch (this) {
        EventSide.light => 'Зелёная команда',
        EventSide.dark => 'Красная команда',
      };

  String get teamTitleRu => switch (this) {
        EventSide.light => 'ЗЕЛЁНАЯ КОМАНДА',
        EventSide.dark => 'КРАСНАЯ КОМАНДА',
      };

  String get assetImage => switch (this) {
        EventSide.light => 'assets/images/side_green.jpg',
        EventSide.dark => 'assets/images/side_red.jpg',
      };
}

class EventImage {
  const EventImage({
    required this.id,
    required this.eventId,
    required this.url,
    required this.sortOrder,
    this.createdAt,
  });

  final String id;
  final String eventId;
  final String url;
  final int sortOrder;
  final DateTime? createdAt;

  factory EventImage.fromJson(Map<String, dynamic> json) {
    return EventImage(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      url: json['url'] as String,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
    );
  }
}

class Event {
  const Event({
    required this.id,
    required this.title,
    required this.description,
    required this.city,
    required this.location,
    required this.eventDate,
    this.organizerId,
    this.organizerNickname,
    this.assistantUserId,
    this.assistantNickname,
    required this.maxParticipants,
    this.imageUrl,
    this.status = EventStatus.active,
    required this.createdAt,
    this.updatedAt,
    this.finishedAt,
    this.reportWinner,
    this.reportScoreLight,
    this.reportScoreDark,
    this.reportSubmittedAt,
    this.participantsCount = 0,
    this.lightParticipantsCount = 0,
    this.darkParticipantsCount = 0,
    this.isParticipating = false,
    this.polygonId,
    this.latitude,
    this.longitude,
    this.rulesId,
    this.rulesText = '',
    this.radioFrequency = '',
    this.mySide,
    this.images = const [],
  });

  final String id;
  final String title;
  final String description;
  final String city;
  final String location;
  final DateTime eventDate;
  final String? organizerId;
  final String? organizerNickname;
  final String? assistantUserId;
  final String? assistantNickname;
  final int maxParticipants;
  final String? imageUrl;
  final EventStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? finishedAt;
  final String? reportWinner;
  final int? reportScoreLight;
  final int? reportScoreDark;
  final DateTime? reportSubmittedAt;
  final int participantsCount;
  final int lightParticipantsCount;
  final int darkParticipantsCount;
  final bool isParticipating;
  final String? polygonId;
  final double? latitude;
  final double? longitude;
  final String? rulesId;
  final String rulesText;
  final String radioFrequency;
  final EventSide? mySide;
  final List<EventImage> images;

  bool get hasMapPoint => latitude != null && longitude != null;

  bool get hasRules => rulesText.trim().isNotEmpty;

  bool get hasRadioFrequency => radioFrequency.trim().isNotEmpty;

  bool get hasReport => reportSubmittedAt != null;

  bool get needsReport =>
      status == EventStatus.finished && reportSubmittedAt == null;

  /// Kept for helpers; public feed no longer shows finished events.
  /// Event chat remains ~3 days after finish (server-side).
  bool get isWithinFinishedWindow {
    if (status != EventStatus.finished) return status == EventStatus.active;
    final at = finishedAt ?? updatedAt ?? createdAt;
    return DateTime.now().toUtc().difference(at.toUtc()) <=
        const Duration(days: 3);
  }

  bool isManager(String? userId) {
    if (userId == null) return false;
    return userId == organizerId || userId == assistantUserId;
  }

  bool isOrganizerOwner(String? userId) =>
      userId != null && userId == organizerId;

  List<String> get galleryUrls {
    if (images.isNotEmpty) {
      return [for (final i in images) if (i.url.trim().isNotEmpty) i.url];
    }
    final cover = imageUrl?.trim();
    if (cover != null && cover.isNotEmpty) return [cover];
    return const [];
  }

  int get slotsLeft =>
      (maxParticipants - participantsCount).clamp(0, maxParticipants);

  bool get isFull => participantsCount >= maxParticipants;

  bool get canRegister =>
      status == EventStatus.active && !isFull && !isParticipating;

  double get fillProgress {
    if (maxParticipants <= 0) return 0;
    return (participantsCount / maxParticipants).clamp(0.0, 1.0);
  }

  String get shortDescription {
    final text = description.trim();
    if (text.length <= 110) return text;
    return '${text.substring(0, 107).trimRight()}…';
  }

  Event copyWith({
    int? participantsCount,
    int? lightParticipantsCount,
    int? darkParticipantsCount,
    bool? isParticipating,
    String? organizerNickname,
    String? assistantUserId,
    String? assistantNickname,
    String? imageUrl,
    EventStatus? status,
    DateTime? finishedAt,
    String? reportWinner,
    int? reportScoreLight,
    int? reportScoreDark,
    DateTime? reportSubmittedAt,
    String? polygonId,
    double? latitude,
    double? longitude,
    String? rulesId,
    String? rulesText,
    String? radioFrequency,
    EventSide? mySide,
    bool clearMySide = false,
    List<EventImage>? images,
  }) {
    return Event(
      id: id,
      title: title,
      description: description,
      city: city,
      location: location,
      eventDate: eventDate,
      organizerId: organizerId,
      organizerNickname: organizerNickname ?? this.organizerNickname,
      assistantUserId: assistantUserId ?? this.assistantUserId,
      assistantNickname: assistantNickname ?? this.assistantNickname,
      maxParticipants: maxParticipants,
      imageUrl: imageUrl ?? this.imageUrl,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      reportWinner: reportWinner ?? this.reportWinner,
      reportScoreLight: reportScoreLight ?? this.reportScoreLight,
      reportScoreDark: reportScoreDark ?? this.reportScoreDark,
      reportSubmittedAt: reportSubmittedAt ?? this.reportSubmittedAt,
      participantsCount: participantsCount ?? this.participantsCount,
      lightParticipantsCount:
          lightParticipantsCount ?? this.lightParticipantsCount,
      darkParticipantsCount:
          darkParticipantsCount ?? this.darkParticipantsCount,
      isParticipating: isParticipating ?? this.isParticipating,
      polygonId: polygonId ?? this.polygonId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      rulesId: rulesId ?? this.rulesId,
      rulesText: rulesText ?? this.rulesText,
      radioFrequency: radioFrequency ?? this.radioFrequency,
      mySide: clearMySide ? null : (mySide ?? this.mySide),
      images: images ?? this.images,
    );
  }

  factory Event.fromJson(
    Map<String, dynamic> json, {
    bool? isParticipating,
    int? participantsCountOverride,
  }) {
    final participantsRaw = json['event_participants'];
    var count = participantsCountOverride ?? 0;
    if (participantsCountOverride == null) {
      if (participantsRaw is List && participantsRaw.isNotEmpty) {
        final first = participantsRaw.first;
        if (first is Map && first['count'] != null) {
          count = (first['count'] as num).toInt();
        }
      } else if (json['participants_count'] != null) {
        count = (json['participants_count'] as num).toInt();
      }
    }

    String? organizerNick;
    final organizer = json['organizer'];
    if (organizer is Map) {
      organizerNick = organizer['nickname'] as String?;
    } else if (organizer is List && organizer.isNotEmpty) {
      final first = organizer.first;
      if (first is Map) {
        organizerNick = first['nickname'] as String?;
      }
    } else if (json['organizer_nickname'] != null) {
      organizerNick = json['organizer_nickname'] as String?;
    }

    String? assistantNick;
    final assistant = json['assistant'];
    if (assistant is Map) {
      assistantNick = assistant['nickname'] as String?;
    } else if (assistant is List && assistant.isNotEmpty) {
      final first = assistant.first;
      if (first is Map) {
        assistantNick = first['nickname'] as String?;
      }
    }

    return Event(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      city: json['city'] as String,
      location: json['location'] as String,
      eventDate: DateTime.parse(json['event_date'] as String),
      organizerId: json['organizer_id'] as String?,
      organizerNickname: organizerNick,
      assistantUserId: json['assistant_user_id'] as String?,
      assistantNickname: assistantNick,
      maxParticipants: (json['max_participants'] as num).toInt(),
      imageUrl: json['image_url'] as String?,
      status: EventStatus.fromString(json['status'] as String?),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String),
      finishedAt: json['finished_at'] == null
          ? null
          : DateTime.parse(json['finished_at'] as String),
      reportWinner: json['report_winner'] as String?,
      reportScoreLight: (json['report_score_light'] as num?)?.toInt(),
      reportScoreDark: (json['report_score_dark'] as num?)?.toInt(),
      reportSubmittedAt: json['report_submitted_at'] == null
          ? null
          : DateTime.parse(json['report_submitted_at'] as String),
      participantsCount: count,
      isParticipating: isParticipating ?? false,
      polygonId: json['polygon_id'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      rulesId: json['rules_id'] as String?,
      rulesText: json['rules_text'] as String? ?? '',
      radioFrequency: json['radio_frequency'] as String? ?? '',
      images: _parseEventImages(json),
    );
  }
}

List<EventImage> _parseEventImages(Map<String, dynamic> json) {
  final raw = json['event_images'] ?? json['images'];
  if (raw is! List) return const [];
  final list = <EventImage>[];
  for (final row in raw) {
    if (row is Map) {
      list.add(EventImage.fromJson(Map<String, dynamic>.from(row)));
    }
  }
  list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  return list;
}

class EventParticipant {
  const EventParticipant({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.registrationStatus,
    required this.attendanceStatus,
    required this.registeredAt,
    this.attendedAt,
    this.confirmedBy,
    this.nickname,
    this.city,
    this.avatarUrl,
    this.publicQrId,
    this.side,
  });

  final String id;
  final String eventId;
  final String userId;
  final RegistrationStatus registrationStatus;
  final AttendanceStatus attendanceStatus;
  final DateTime registeredAt;
  final DateTime? attendedAt;
  final String? confirmedBy;
  final String? nickname;
  final String? city;
  final String? avatarUrl;
  final String? publicQrId;
  final EventSide? side;

  bool get isConfirmed => attendanceStatus == AttendanceStatus.confirmed;

  factory EventParticipant.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? profile;
    final raw = json['profile'] ?? json['profiles'];
    if (raw is Map) {
      profile = Map<String, dynamic>.from(raw);
    }

    return EventParticipant(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      userId: json['user_id'] as String,
      registrationStatus: RegistrationStatus.fromString(
        json['registration_status'] as String?,
      ),
      attendanceStatus: AttendanceStatus.fromString(
        json['attendance_status'] as String?,
      ),
      registeredAt: DateTime.parse(
        (json['registered_at'] ?? json['created_at']) as String,
      ),
      attendedAt: json['attended_at'] == null
          ? null
          : DateTime.parse(json['attended_at'] as String),
      confirmedBy: json['confirmed_by'] as String?,
      nickname: profile?['nickname'] as String? ?? json['nickname'] as String?,
      city: profile?['city'] as String? ?? json['city'] as String?,
      avatarUrl:
          profile?['avatar_url'] as String? ?? json['avatar_url'] as String?,
      publicQrId: profile?['public_qr_id'] as String? ??
          json['public_qr_id'] as String?,
      side: EventSide.fromString(json['side'] as String?),
    );
  }

  EventParticipant copyWith({
    AttendanceStatus? attendanceStatus,
    DateTime? attendedAt,
    String? confirmedBy,
    EventSide? side,
  }) {
    return EventParticipant(
      id: id,
      eventId: eventId,
      userId: userId,
      registrationStatus: registrationStatus,
      attendanceStatus: attendanceStatus ?? this.attendanceStatus,
      registeredAt: registeredAt,
      attendedAt: attendedAt ?? this.attendedAt,
      confirmedBy: confirmedBy ?? this.confirmedBy,
      nickname: nickname,
      city: city,
      avatarUrl: avatarUrl,
      publicQrId: publicQrId,
      side: side ?? this.side,
    );
  }
}

class AttendanceConfirmResult {
  const AttendanceConfirmResult({
    required this.userId,
    required this.nickname,
    required this.city,
    required this.eventId,
    required this.eventTitle,
    required this.attendedAt,
    this.avatarUrl,
    this.rewardAmount = 0,
    this.balance = 0,
    this.currency = 'credits',
    this.pendingSync = false,
  });

  final String userId;
  final String nickname;
  final String city;
  final String eventId;
  final String eventTitle;
  final DateTime attendedAt;
  final String? avatarUrl;
  final num rewardAmount;
  final num balance;
  final String currency;
  /// Confirmed locally without network; will sync when online.
  final bool pendingSync;

  String get rewardLabel => '+${_fmt(rewardAmount)} CR';
  String get balanceLabel => '${_fmt(balance)} CR';

  static String _fmt(num v) {
    if (v == v.roundToDouble()) return '${v.toInt()}';
    return v.toStringAsFixed(2);
  }

  factory AttendanceConfirmResult.fromJson(Map<String, dynamic> json) {
    return AttendanceConfirmResult(
      userId: json['user_id'] as String,
      nickname: (json['nickname'] as String?) ?? 'Боец',
      city: (json['city'] as String?) ?? '',
      eventId: json['event_id'] as String,
      eventTitle: (json['event_title'] as String?) ?? 'Мероприятие',
      attendedAt: DateTime.parse(json['attended_at'] as String),
      avatarUrl: json['avatar_url'] as String?,
      rewardAmount: (json['reward_amount'] as num?) ?? 0,
      balance: (json['balance'] as num?) ?? 0,
      currency: (json['currency'] as String?) ?? 'credits',
    );
  }
}
