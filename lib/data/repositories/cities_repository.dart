import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/cities.dart';

/// Loads active cities from Supabase `app_cities` (fallback to local list).
class CitiesRepository {
  CitiesRepository(this._client);

  final SupabaseClient _client;

  Future<List<String>> fetchActiveNames() async {
    try {
      final rows = await _client.rpc('list_active_cities');
      final list = (rows as List)
          .map((e) => (e as Map)['name'] as String)
          .where((n) => n.trim().isNotEmpty)
          .toList();
      if (list.isNotEmpty) return list;
    } catch (_) {}
    return List<String>.from(Cities.all);
  }
}
