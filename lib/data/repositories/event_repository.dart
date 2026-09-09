import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/app_exception.dart';
import '../../core/utils/error_mapper.dart';
import '../../domain/models/event.dart';

class EventRepository {
  EventRepository(this._client);

  final SupabaseClient _client;

  static const _select = '''
    id,
    title,
    description,
    city,
    location,
    event_date,
    organizer_id,
    max_participants,
    image_url,
    status,
    created_at,
    updated_at,
    polygon_id,
    latitude,
    longitude,
    organizer:profiles!organizer_id(nickname)
  ''';

  Future<List<Event>> fetchEvents({String? city}) async {
    try {
      var query = _client.from('events').select(_select);

      if (city != null && city.isNotEmpty) {
        query = query.eq('city', city);
      }

      // Public feed: active (+ optionally finished later)
      query = query.inFilter('status', ['active', 'finished']);

      final rows = await query.order('event_date', ascending: true);
      return _hydrateList(rows as List);
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<List<Event>> fetchMyOrganizerEvents() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) throw const AppException('Требуется авторизация');

      final rows = await _client
          .from('events')
          .select(_select)
          .eq('organizer_id', uid)
          .order('event_date', ascending: false)
          .timeout(const Duration(seconds: 15));

      return _hydrateList(rows as List);
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<Event> fetchById(String id) async {
    try {
      final row = await _client
          .from('events')
          .select(_select)
          .eq('id', id)
          .single();

      final list = await _hydrateList([row]);
      return list.first;
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<List<Event>> _hydrateList(List rows) async {
    final base = [
      for (final e in rows)
        Event.fromJson(Map<String, dynamic>.from(e as Map)),
    ];
    if (base.isEmpty) return base;

    final ids = base.map((e) => e.id).toList();
    final counts = <String, int>{};
    try {
      final partRows = await _client
          .from('event_participants')
          .select('event_id')
          .eq('registration_status', 'registered')
          .inFilter('event_id', ids);
      for (final raw in partRows as List) {
        final id = (raw as Map)['event_id'] as String;
        counts[id] = (counts[id] ?? 0) + 1;
      }
    } catch (_) {}

    final userId = _client.auth.currentUser?.id;
    final joinedIds = <String>{};
    if (userId != null) {
      try {
        final joined = await _client
            .from('event_participants')
            .select('event_id')
            .eq('user_id', userId)
            .eq('registration_status', 'registered')
            .inFilter('event_id', ids);
        for (final row in joined as List) {
          joinedIds.add((row as Map)['event_id'] as String);
        }
      } catch (_) {}
    }

    return [
      for (final event in base)
        event.copyWith(
          participantsCount: counts[event.id] ?? 0,
          isParticipating: joinedIds.contains(event.id),
        ),
    ];
  }

  Future<int> getUserEventsCount(String userId) async {
    try {
      final rows = await _client
          .from('event_participants')
          .select('id')
          .eq('user_id', userId)
          .eq('registration_status', 'registered');
      return (rows as List).length;
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<int> countParticipants(String eventId) async {
    try {
      final rows = await _client
          .from('event_participants')
          .select('id')
          .eq('event_id', eventId)
          .eq('registration_status', 'registered');
      return (rows as List).length;
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<List<EventParticipant>> fetchParticipants(String eventId) async {
    try {
      final rows = await _client
          .from('event_participants')
          .select(
            'id, event_id, user_id, registration_status, attendance_status, '
            'registered_at, attended_at, confirmed_by, '
            'profile:profiles!user_id(nickname, city, avatar_url)',
          )
          .eq('event_id', eventId)
          .eq('registration_status', 'registered')
          .order('registered_at', ascending: true)
          .timeout(const Duration(seconds: 15));

      return [
        for (final raw in rows as List)
          EventParticipant.fromJson(Map<String, dynamic>.from(raw as Map)),
      ];
    } catch (e) {
      // Fallback if FK embed name differs
      try {
        final rows = await _client
            .from('event_participants')
            .select()
            .eq('event_id', eventId)
            .eq('registration_status', 'registered')
            .order('registered_at', ascending: true);
        final list = <EventParticipant>[];
        for (final raw in rows as List) {
          final map = Map<String, dynamic>.from(raw as Map);
          final profile = await _client
              .from('profiles')
              .select('nickname, city, avatar_url')
              .eq('id', map['user_id'] as String)
              .maybeSingle();
          if (profile != null) {
            map['nickname'] = profile['nickname'];
            map['city'] = profile['city'];
            map['avatar_url'] = profile['avatar_url'];
          }
          list.add(EventParticipant.fromJson(map));
        }
        return list;
      } catch (e2) {
        throw AppException(ErrorMapper.map(e2));
      }
    }
  }

  Future<String> createEvent({
    required String title,
    required String description,
    required String city,
    required String location,
    required DateTime eventDate,
    required int maxParticipants,
    String? imageUrl,
    EventStatus status = EventStatus.active,
    String? polygonId,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final result = await _client.rpc(
        'create_event',
        params: {
          'p_title': title,
          'p_description': description,
          'p_city': city,
          'p_location': location,
          'p_event_date': eventDate.toUtc().toIso8601String(),
          'p_max_participants': maxParticipants,
          'p_image_url': imageUrl,
          'p_status': status.dbValue,
          'p_polygon_id': polygonId,
          'p_latitude': latitude,
          'p_longitude': longitude,
        },
      );
      return result as String;
    } catch (e) {
      throw AppException(_mapEventError(e));
    }
  }

  Future<void> setEventImageUrl({
    required String eventId,
    required String imageUrl,
  }) async {
    try {
      await _client
          .from('events')
          .update({'image_url': imageUrl})
          .eq('id', eventId);
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<void> deleteEvent(String eventId) async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) throw const AppException('Требуется авторизация');

      await _client
          .from('events')
          .delete()
          .eq('id', eventId)
          .eq('organizer_id', uid)
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException(_mapEventError(e));
    }
  }

  Future<void> finishEvent(String eventId) async {
    try {
      await _client.rpc('finish_event', params: {'p_event_id': eventId});
    } catch (e) {
      throw AppException(_mapEventError(e));
    }
  }

  Future<Event> join(String eventId) async {
    try {
      await _client.rpc('join_event', params: {'p_event_id': eventId});
      return fetchById(eventId);
    } catch (e) {
      throw AppException(_mapEventError(e));
    }
  }

  Future<Event> leave(String eventId) async {
    try {
      await _client.rpc('leave_event', params: {'p_event_id': eventId});
      return fetchById(eventId);
    } catch (e) {
      throw AppException(_mapEventError(e));
    }
  }

  Future<AttendanceConfirmResult> confirmAttendance({
    required String eventId,
    required String publicQrId,
  }) async {
    try {
      final row = await _client.rpc(
        'confirm_event_attendance',
        params: {
          'p_event_id': eventId,
          'p_public_qr_id': publicQrId,
        },
      );
      return AttendanceConfirmResult.fromJson(
        Map<String, dynamic>.from(row as Map),
      );
    } catch (e) {
      throw AppException(_mapEventError(e));
    }
  }

  /// Parse `tactical:qr:<uuid>` or bare UUID.
  static String? parseQrToken(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final prefix = 'tactical:qr:';
    if (text.toLowerCase().startsWith(prefix)) {
      return text.substring(prefix.length).trim();
    }
    // UUID-ish
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    if (uuid.hasMatch(text)) return text;
    return null;
  }

  String _mapEventError(Object e) {
    final msg = '${ErrorMapper.map(e)} $e'.toUpperCase();
    if (msg.contains('NO_SLOTS')) return 'Мест нет';
    if (msg.contains('EVENT_NOT_ACTIVE')) return 'Мероприятие недоступно';
    if (msg.contains('EVENT_FINISHED')) return 'Мероприятие завершено';
    if (msg.contains('EVENT_CANCELLED')) return 'Мероприятие отменено';
    if (msg.contains('USER_NOT_FOUND')) return 'Пользователь не найден';
    if (msg.contains('NOT_REGISTERED')) {
      return 'Пользователь не зарегистрирован на это мероприятие';
    }
    if (msg.contains('ALREADY_CONFIRMED')) {
      return 'Присутствие уже подтверждено';
    }
    if (msg.contains('NOT_EVENT_OWNER') || msg.contains('FORBIDDEN')) {
      return 'Нет доступа';
    }
    if (msg.contains('EVENT_NOT_FOUND')) return 'Мероприятие не найдено';
    if (msg.contains('MAP_LOCATION_REQUIRED')) {
      return 'Укажите точку на карте или выберите полигон';
    }
    if (msg.contains('INVALID_COORDINATES')) return 'Некорректные координаты';
    if (msg.contains('POLYGON_NOT_FOUND')) return 'Полигон не найден';
    return ErrorMapper.map(e);
  }

  RealtimeChannel subscribeParticipants({
    required String channelName,
    required void Function() onChange,
  }) {
    final channel = _client.channel(channelName);
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'event_participants',
          callback: (_) => onChange(),
        )
        .subscribe();
    return channel;
  }
}
