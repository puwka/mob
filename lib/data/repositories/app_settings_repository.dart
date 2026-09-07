import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads runtime limits from `app_settings` (admin-editable).
class AppSettingsRepository {
  AppSettingsRepository(this._client);

  final SupabaseClient _client;

  Future<int> getInt(String key, {required int fallback}) async {
    try {
      final value = await _client.rpc('get_app_setting', params: {'p_key': key});
      if (value == null) return fallback;
      return int.tryParse(value.toString()) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<int> profilePhotosLimit() =>
      getInt('profile_photos_limit', fallback: 4);

  Future<int> listingImagesLimit() =>
      getInt('listing_images_limit', fallback: 8);
}
