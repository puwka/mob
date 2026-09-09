import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/app_exception.dart';
import '../../core/utils/error_mapper.dart';
import '../../domain/models/polygon.dart';

class PolygonRepository {
  PolygonRepository(this._client);

  final SupabaseClient _client;

  static const _select =
      'id, organizer_id, name, city, address, latitude, longitude, created_at, updated_at';

  Future<List<PolygonVenue>> fetchMine() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) throw const AppException('Требуется авторизация');

      final rows = await _client
          .from('polygons')
          .select(_select)
          .eq('organizer_id', uid)
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 15));

      return [
        for (final raw in rows as List)
          PolygonVenue.fromJson(Map<String, dynamic>.from(raw as Map)),
      ];
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<String> create({
    required String name,
    required String city,
    required String address,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final id = await _client.rpc(
        'create_polygon',
        params: {
          'p_name': name,
          'p_city': city,
          'p_address': address,
          'p_latitude': latitude,
          'p_longitude': longitude,
        },
      );
      return id as String;
    } catch (e) {
      throw AppException(_map(e));
    }
  }

  Future<void> update({
    required String id,
    required String name,
    required String city,
    required String address,
    required double latitude,
    required double longitude,
  }) async {
    try {
      await _client.rpc(
        'update_polygon',
        params: {
          'p_polygon_id': id,
          'p_name': name,
          'p_city': city,
          'p_address': address,
          'p_latitude': latitude,
          'p_longitude': longitude,
        },
      );
    } catch (e) {
      throw AppException(_map(e));
    }
  }

  Future<void> delete(String id) async {
    try {
      await _client.rpc('delete_polygon', params: {'p_polygon_id': id});
    } catch (e) {
      throw AppException(_map(e));
    }
  }

  String _map(Object e) {
    final msg = '${ErrorMapper.map(e)} $e'.toUpperCase();
    if (msg.contains('INVALID_POLYGON_NAME')) return 'Укажите название полигона';
    if (msg.contains('INVALID_ADDRESS')) return 'Укажите адрес';
    if (msg.contains('INVALID_COORDINATES')) return 'Укажите точку на карте';
    if (msg.contains('POLYGON_NOT_FOUND')) return 'Полигон не найден';
    if (msg.contains('FORBIDDEN')) return 'Нет доступа';
    return ErrorMapper.map(e);
  }
}
