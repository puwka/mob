import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/app_exception.dart';
import '../../core/utils/error_mapper.dart';
import '../../domain/models/clan.dart';

class ClanRepository {
  ClanRepository(this._client);

  final SupabaseClient _client;

  String? get _uid => _client.auth.currentUser?.id;

  Future<Clan?> fetchMyClan() async {
    try {
      final uid = _uid;
      if (uid == null) return null;
      return fetchClanForUser(uid);
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<Clan?> fetchClanForUser(String userId) async {
    try {
      final membership = await _client
          .from('clan_members')
          .select('clan_id')
          .eq('user_id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 12));
      if (membership == null) return null;
      return fetchClan(membership['clan_id'] as String);
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<Clan> fetchClan(String clanId) async {
    try {
      try {
        final row = await _client
            .from('clans_with_stats')
            .select()
            .eq('id', clanId)
            .single()
            .timeout(const Duration(seconds: 12));
        final map = Map<String, dynamic>.from(row);
        // Legacy view may omit city (created before column existed).
        if (map['city'] == null) {
          final base = await _client
              .from('clans')
              .select('city')
              .eq('id', clanId)
              .maybeSingle()
              .timeout(const Duration(seconds: 8));
          if (base != null) map['city'] = base['city'];
        }
        return Clan.fromJson(map);
      } catch (_) {
        final row = await _client
            .from('clans')
            .select()
            .eq('id', clanId)
            .single()
            .timeout(const Duration(seconds: 12));
        final map = Map<String, dynamic>.from(row);
        final count = await _client
            .from('clan_members')
            .select('user_id')
            .eq('clan_id', clanId);
        map['members_count'] = (count as List).length;
        if (map['leader_id'] != null) {
          final leader = await _client
              .from('profiles')
              .select('nickname')
              .eq('id', map['leader_id'] as String)
              .maybeSingle();
          map['leader_nickname'] = leader?['nickname'];
        }
        return Clan.fromJson(map);
      }
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<List<Clan>> searchClans({
    String query = '',
    String? city,
  }) async {
    try {
      final q = query.trim();
      final cityTrim = city?.trim() ?? '';
      // Clan directory is city-scoped; without a city there is nothing to list.
      if (cityTrim.isEmpty) return const [];

      List rows;
      try {
        var req = _client.from('clans_with_stats').select().eq('city', cityTrim);
        if (q.isNotEmpty) {
          final safe = q.replaceAll(',', ' ');
          req = req.or('name.ilike.%$safe%,tag.ilike.%$safe%');
        }
        rows = await req
                .order('rating', ascending: false)
                .limit(50)
                .timeout(const Duration(seconds: 15))
            as List;
      } catch (_) {
        var req = _client.from('clans').select().eq('city', cityTrim);
        if (q.isNotEmpty) {
          final safe = q.replaceAll(',', ' ');
          req = req.or('name.ilike.%$safe%,tag.ilike.%$safe%');
        }
        final raw = await req
            .order('rating', ascending: false)
            .limit(50)
            .timeout(const Duration(seconds: 15));
        rows = [];
        for (final r in raw as List) {
          final map = Map<String, dynamic>.from(r as Map);
          final members = await _client
              .from('clan_members')
              .select('user_id')
              .eq('clan_id', map['id'] as String);
          map['members_count'] = (members as List).length;
          rows.add(map);
        }
      }
      final cityLower = cityTrim.toLowerCase();
      return [
        for (final r in rows)
          Clan.fromJson(Map<String, dynamic>.from(r as Map)),
      ].where((c) => (c.city ?? '').trim().toLowerCase() == cityLower).toList();
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<List<ClanMember>> fetchMembers(String clanId) async {
    try {
      final rows = await _client
          .from('clan_members')
          .select('clan_id, user_id, role, joined_at')
          .eq('clan_id', clanId)
          .timeout(const Duration(seconds: 12));

      final rawList = (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (rawList.isEmpty) return const [];

      final userIds = [
        for (final m in rawList) m['user_id'] as String,
      ];
      final profilesById = await _fetchProfilesByIds(userIds);

      final members = <ClanMember>[];
      for (final map in rawList) {
        final profile = profilesById[map['user_id'] as String];
        map['nickname'] = profile?['nickname'] ?? 'Боец';
        map['rating'] = profile?['rating'] ?? 0;
        map['avatar_url'] = profile?['avatar_url'];
        members.add(ClanMember.fromJson(map));
      }

      members.sort((a, b) {
        final roleCmp = a.role.index.compareTo(b.role.index);
        if (roleCmp != 0) return roleCmp;
        return b.rating.compareTo(a.rating);
      });
      return members;
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<Map<String, Map<String, dynamic>>> _fetchProfilesByIds(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return const {};
    final rows = await _client
        .from('profiles')
        .select('id, nickname, rating, avatar_url')
        .inFilter('id', userIds)
        .timeout(const Duration(seconds: 12));
    final out = <String, Map<String, dynamic>>{};
    for (final raw in rows as List) {
      final map = Map<String, dynamic>.from(raw as Map);
      out[map['id'] as String] = map;
    }
    return out;
  }

  Future<String> createClan({
    required String name,
    required String tag,
    required String description,
    required String city,
    String? avatarUrl,
  }) async {
    try {
      final id = await _client.rpc(
        'create_clan',
        params: {
          'p_name': name,
          'p_tag': tag,
          'p_description': description,
          'p_avatar_url': avatarUrl,
          'p_city': city,
        },
      );
      return id as String;
    } catch (e) {
      throw AppException(_map(e));
    }
  }

  Future<Clan> updateClanInfo({
    required String clanId,
    String? city,
    String? description,
  }) async {
    try {
      final row = await _client.rpc(
        'update_clan_info',
        params: {
          'p_clan_id': clanId,
          'p_city': city,
          'p_description': description,
        },
      );
      return Clan.fromJson(Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw AppException(_map(e));
    }
  }

  Future<void> setClanAvatarUrl({
    required String clanId,
    required String avatarUrl,
  }) async {
    try {
      await _client.rpc(
        'set_clan_avatar',
        params: {
          'p_clan_id': clanId,
          'p_avatar_url': avatarUrl,
        },
      );
    } catch (e) {
      throw AppException(_map(e));
    }
  }

  Future<String> requestJoin(String clanId) async {
    try {
      final id = await _client.rpc(
        'request_clan_join',
        params: {'p_clan_id': clanId},
      );
      return id as String;
    } catch (e) {
      throw AppException(_map(e));
    }
  }

  Future<void> decideJoin({
    required String requestId,
    required bool approve,
  }) async {
    try {
      await _client.rpc(
        'decide_clan_join',
        params: {
          'p_request_id': requestId,
          'p_approve': approve,
        },
      );
    } catch (e) {
      throw AppException(_map(e));
    }
  }

  Future<void> leaveClan() async {
    try {
      await _client.rpc('leave_clan');
    } catch (e) {
      throw AppException(_map(e));
    }
  }

  Future<void> kickMember(String userId) async {
    try {
      await _client.rpc(
        'kick_clan_member',
        params: {'p_user_id': userId},
      );
    } catch (e) {
      throw AppException(_map(e));
    }
  }

  Future<List<ClanJoinRequest>> fetchPendingRequests(String clanId) async {
    try {
      final rows = await _client
          .from('clan_join_requests')
          .select('id, clan_id, user_id, status, created_at')
          .eq('clan_id', clanId)
          .eq('status', 'pending')
          .order('created_at', ascending: true)
          .timeout(const Duration(seconds: 12));

      final rawList = (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (rawList.isEmpty) return const [];

      final userIds = [
        for (final r in rawList) r['user_id'] as String,
      ];
      final profilesById = await _fetchProfilesByIds(userIds);

      final list = <ClanJoinRequest>[];
      for (final map in rawList) {
        final profile = profilesById[map['user_id'] as String];
        map['profile'] = {
          'nickname': profile?['nickname'],
          'rating': profile?['rating'] ?? 0,
          'avatar_url': profile?['avatar_url'],
        };
        list.add(ClanJoinRequest.fromJson(map));
      }
      return list;
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<ClanJoinStatus?> myRequestStatus(String clanId) async {
    try {
      final uid = _uid;
      if (uid == null) return null;
      final row = await _client
          .from('clan_join_requests')
          .select('status')
          .eq('clan_id', clanId)
          .eq('user_id', uid)
          .maybeSingle();
      if (row == null) return null;
      return ClanJoinStatus.fromString(row['status'] as String);
    } catch (_) {
      return null;
    }
  }

  Future<ClanRole?> myRoleIn(String clanId) async {
    try {
      final uid = _uid;
      if (uid == null) return null;
      final row = await _client
          .from('clan_members')
          .select('role')
          .eq('clan_id', clanId)
          .eq('user_id', uid)
          .maybeSingle();
      if (row == null) return null;
      return ClanRole.fromString(row['role'] as String);
    } catch (_) {
      return null;
    }
  }

  Future<void> setMemberRole({
    required String userId,
    required ClanRole role,
  }) async {
    try {
      if (role == ClanRole.leader) {
        throw const AppException('Нельзя назначить командира');
      }
      await _client.rpc(
        'set_clan_member_role',
        params: {
          'p_user_id': userId,
          'p_role': role.dbValue,
        },
      ).timeout(const Duration(seconds: 12));
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException(_map(e));
    }
  }

  String _map(Object e) {
    final raw = e.toString().toUpperCase();
    if (raw.contains('NAME_TAKEN')) return 'Название клана уже занято';
    if (raw.contains('TAG_TAKEN')) return 'TAG уже занят';
    if (raw.contains('INVALID_NAME')) return 'Некорректное название клана';
    if (raw.contains('INVALID_TAG')) {
      return 'TAG: 2–6 символов (A-Z, 0-9)';
    }
    if (raw.contains('LEVEL_TOO_LOW')) {
      return 'Создать клан можно с 3 уровня';
    }
    if (raw.contains('ALREADY_IN_CLAN')) {
      return 'Вы уже состоите в клане';
    }
    if (raw.contains('NOT_IN_CLAN')) return 'Вы не состоите в клане';
    if (raw.contains('INVALID_CLAN_ROLE')) return 'Некорректная должность';
    if (raw.contains('INVALID_CITY')) return 'Укажите местоположение клана';
    if (raw.contains('NOT_CLAN_LEADER')) {
      return 'Только командир может менять данные клана';
    }
    if (raw.contains('NOT_ALLOWED')) return 'Недостаточно прав';
    if (raw.contains('CLAN_NOT_FOUND')) return 'Клан не найден';
    if (raw.contains('REQUEST_NOT_FOUND')) return 'Заявка не найдена';
    if (raw.contains('REQUEST_NOT_PENDING')) return 'Заявка уже обработана';
    return ErrorMapper.map(e);
  }
}
