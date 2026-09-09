import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/event.dart';
import '../domain/models/profile.dart';

/// Durable local cache for offline QR show + scan on polygons.
class OfflineQrStore {
  OfflineQrStore(this._prefs);

  final SharedPreferences _prefs;

  static const _ownPrefix = 'offline_own_qr_v1_';
  static const _rosterPrefix = 'offline_event_roster_v1_';
  static const _eventsPrefix = 'offline_org_events_v1_';
  static const _pendingKey = 'offline_pending_attendance_v1';

  static Future<OfflineQrStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    return OfflineQrStore(prefs);
  }

  Future<void> saveOwnProfile(Profile profile) async {
    if (profile.publicQrId == null || profile.publicQrId!.isEmpty) return;
    final payload = {
      'id': profile.id,
      'phone': profile.phone,
      'nickname': profile.nickname,
      'city': profile.city,
      'avatar_url': profile.avatarUrl,
      'public_qr_id': profile.publicQrId,
      'role': profile.appRole.dbValue,
      'badge_role': profile.badgeRole.name,
      'game_role': profile.gameRole,
      'created_at': profile.createdAt.toIso8601String(),
    };
    await _prefs.setString('$_ownPrefix${profile.id}', jsonEncode(payload));
  }

  Profile? loadOwnProfile(String userId) {
    final raw = _prefs.getString('$_ownPrefix$userId');
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return Profile.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveOrganizerEvents({
    required String organizerId,
    required List<Event> events,
  }) async {
    final payload = [
      for (final e in events)
        {
          'id': e.id,
          'title': e.title,
          'description': e.description,
          'city': e.city,
          'location': e.location,
          'event_date': e.eventDate.toIso8601String(),
          'organizer_id': e.organizerId ?? organizerId,
          'max_participants': e.maxParticipants,
          'image_url': e.imageUrl,
          'status': e.status.dbValue,
          'created_at': e.createdAt.toIso8601String(),
          'participants_count': e.participantsCount,
          'polygon_id': e.polygonId,
          'latitude': e.latitude,
          'longitude': e.longitude,
        },
    ];
    await _prefs.setString('$_eventsPrefix$organizerId', jsonEncode(payload));
  }

  List<Event> loadOrganizerEvents(String organizerId) {
    final raw = _prefs.getString('$_eventsPrefix$organizerId');
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final row in list)
          Event.fromJson(Map<String, dynamic>.from(row as Map)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveEventRoster({
    required String eventId,
    required String eventTitle,
    required List<EventParticipant> participants,
  }) async {
    final payload = {
      'event_id': eventId,
      'event_title': eventTitle,
      'cached_at': DateTime.now().toIso8601String(),
      'participants': [
        for (final p in participants)
          {
            'id': p.id,
            'event_id': p.eventId,
            'user_id': p.userId,
            'registration_status': p.registrationStatus ==
                    RegistrationStatus.cancelled
                ? 'cancelled'
                : 'registered',
            'attendance_status':
                p.isConfirmed ? 'confirmed' : 'not_confirmed',
            'registered_at': p.registeredAt.toIso8601String(),
            'attended_at': p.attendedAt?.toIso8601String(),
            'confirmed_by': p.confirmedBy,
            'nickname': p.nickname,
            'city': p.city,
            'avatar_url': p.avatarUrl,
            'public_qr_id': p.publicQrId,
          },
      ],
    };
    await _prefs.setString('$_rosterPrefix$eventId', jsonEncode(payload));
  }

  OfflineEventRoster? loadEventRoster(String eventId) {
    final raw = _prefs.getString('$_rosterPrefix$eventId');
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final participants = <EventParticipant>[
        for (final row in (map['participants'] as List? ?? const []))
          EventParticipant.fromJson(Map<String, dynamic>.from(row as Map)),
      ];
      return OfflineEventRoster(
        eventId: map['event_id'] as String? ?? eventId,
        eventTitle: map['event_title'] as String? ?? 'Мероприятие',
        cachedAt: DateTime.tryParse(map['cached_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        participants: participants,
      );
    } catch (_) {
      return null;
    }
  }

  List<PendingAttendanceScan> loadPendingScans() {
    final raw = _prefs.getString(_pendingKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final row in list)
          PendingAttendanceScan.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> savePendingScans(List<PendingAttendanceScan> scans) async {
    final payload = [for (final s in scans) s.toJson()];
    await _prefs.setString(_pendingKey, jsonEncode(payload));
  }

  Future<void> enqueuePending(PendingAttendanceScan scan) async {
    final list = [...loadPendingScans()];
    final exists = list.any(
      (s) =>
          s.eventId == scan.eventId && s.publicQrId == scan.publicQrId,
    );
    if (exists) return;
    list.add(scan);
    await savePendingScans(list);
  }

  Future<void> removePending(String id) async {
    final list = loadPendingScans().where((s) => s.id != id).toList();
    await savePendingScans(list);
  }

  Future<void> clearUser(String userId) async {
    await _prefs.remove('$_ownPrefix$userId');
    await _prefs.remove('$_eventsPrefix$userId');
    // Keep pending/rosters keyed by event — drop all known rosters for safety.
    final keys = _prefs.getKeys().toList();
    for (final key in keys) {
      if (key.startsWith(_rosterPrefix) || key == _pendingKey) {
        await _prefs.remove(key);
      }
    }
  }
}

class OfflineEventRoster {
  const OfflineEventRoster({
    required this.eventId,
    required this.eventTitle,
    required this.cachedAt,
    required this.participants,
  });

  final String eventId;
  final String eventTitle;
  final DateTime cachedAt;
  final List<EventParticipant> participants;

  EventParticipant? findByPublicQrId(String publicQrId) {
    final needle = publicQrId.trim().toLowerCase();
    for (final p in participants) {
      final id = p.publicQrId?.trim().toLowerCase();
      if (id != null && id == needle) return p;
    }
    return null;
  }
}

class PendingAttendanceScan {
  const PendingAttendanceScan({
    required this.id,
    required this.eventId,
    required this.eventTitle,
    required this.publicQrId,
    required this.userId,
    required this.nickname,
    required this.city,
    required this.scannedAt,
    this.avatarUrl,
  });

  final String id;
  final String eventId;
  final String eventTitle;
  final String publicQrId;
  final String userId;
  final String nickname;
  final String city;
  final DateTime scannedAt;
  final String? avatarUrl;

  Map<String, dynamic> toJson() => {
        'id': id,
        'event_id': eventId,
        'event_title': eventTitle,
        'public_qr_id': publicQrId,
        'user_id': userId,
        'nickname': nickname,
        'city': city,
        'scanned_at': scannedAt.toIso8601String(),
        'avatar_url': avatarUrl,
      };

  factory PendingAttendanceScan.fromJson(Map<String, dynamic> json) {
    return PendingAttendanceScan(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      eventTitle: (json['event_title'] as String?) ?? 'Мероприятие',
      publicQrId: json['public_qr_id'] as String,
      userId: json['user_id'] as String,
      nickname: (json['nickname'] as String?) ?? 'Боец',
      city: (json['city'] as String?) ?? '',
      scannedAt: DateTime.parse(json['scanned_at'] as String),
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}
