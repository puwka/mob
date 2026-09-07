import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/app_exception.dart';
import '../../core/utils/error_mapper.dart';
import '../../domain/models/ranking.dart';

class RankingRepository {
  RankingRepository(this._client);

  final SupabaseClient _client;

  static const pageSize = 20;

  Future<List<RankingPlayerEntry>> fetchPlayers({
    String? city,
    int offset = 0,
    int limit = pageSize,
  }) async {
    try {
      final rows = await _client.rpc(
        'ranking_players',
        params: {
          'p_city': _cityParam(city),
          'p_limit': limit,
          'p_offset': offset,
        },
      ).timeout(const Duration(seconds: 15));

      return (rows as List)
          .map((e) => RankingPlayerEntry.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList();
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<RankingPlayerEntry?> fetchMyPlayerRank({String? city}) async {
    try {
      final rows = await _client.rpc(
        'ranking_my_player',
        params: {'p_city': _cityParam(city)},
      ).timeout(const Duration(seconds: 12));

      final list = rows as List;
      if (list.isEmpty) return null;
      return RankingPlayerEntry.fromJson(
        Map<String, dynamic>.from(list.first as Map),
      );
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<List<RankingClanEntry>> fetchClans({
    String? city,
    int offset = 0,
    int limit = pageSize,
  }) async {
    try {
      final rows = await _client.rpc(
        'ranking_clans',
        params: {
          'p_city': _cityParam(city),
          'p_limit': limit,
          'p_offset': offset,
        },
      ).timeout(const Duration(seconds: 15));

      return (rows as List)
          .map((e) => RankingClanEntry.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList();
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<RankingClanEntry?> fetchMyClanRank({String? city}) async {
    try {
      final rows = await _client.rpc(
        'ranking_my_clan',
        params: {'p_city': _cityParam(city)},
      ).timeout(const Duration(seconds: 12));

      final list = rows as List;
      if (list.isEmpty) return null;
      return RankingClanEntry.fromJson(
        Map<String, dynamic>.from(list.first as Map),
      );
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  String? _cityParam(String? city) {
    final t = city?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }
}
