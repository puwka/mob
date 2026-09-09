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
    required this.maxParticipants,
    this.imageUrl,
    this.status = EventStatus.active,
    required this.createdAt,
    this.updatedAt,
    this.participantsCount = 0,
    this.isParticipating = false,
    this.polygonId,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String title;
  final String description;
  final String city;
  final String location;
  final DateTime eventDate;
  final String? organizerId;
  final String? organizerNickname;
  final int maxParticipants;
  final String? imageUrl;
  final EventStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int participantsCount;
  final bool isParticipating;
  final String? polygonId;
  final double? latitude;
  final double? longitude;

  bool get hasMapPoint => latitude != null && longitude != null;

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
    bool? isParticipating,
    String? organizerNickname,
    String? imageUrl,
    EventStatus? status,
    String? polygonId,
    double? latitude,
    double? longitude,
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
      maxParticipants: maxParticipants,
      imageUrl: imageUrl ?? this.imageUrl,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt,
      participantsCount: participantsCount ?? this.participantsCount,
      isParticipating: isParticipating ?? this.isParticipating,
      polygonId: polygonId ?? this.polygonId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
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

    return Event(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      city: json['city'] as String,
      location: json['location'] as String,
      eventDate: DateTime.parse(json['event_date'] as String),
      organizerId: json['organizer_id'] as String?,
      organizerNickname: organizerNick,
      maxParticipants: (json['max_participants'] as num).toInt(),
      imageUrl: json['image_url'] as String?,
      status: EventStatus.fromString(json['status'] as String?),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String),
      participantsCount: count,
      isParticipating: isParticipating ?? false,
      polygonId: json['polygon_id'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }
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
    );
  }

  EventParticipant copyWith({
    AttendanceStatus? attendanceStatus,
    DateTime? attendedAt,
    String? confirmedBy,
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
