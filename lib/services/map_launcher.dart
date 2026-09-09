import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../core/utils/app_exception.dart';

/// Opens an external maps app for the given coordinates or search query.
class MapLauncher {
  static Future<void> open({
    double? latitude,
    double? longitude,
    String? query,
  }) async {
    final hasCoords = latitude != null && longitude != null;
    final q = (query ?? '').trim();
    if (!hasCoords && q.isEmpty) {
      throw const AppException('Адрес не указан');
    }

    final Uri uri;
    if (hasCoords) {
      uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
      );
    } else {
      uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(q)}',
      );
    }

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      throw const AppException('Не удалось открыть карту');
    }
  }
}

/// Lightweight Nominatim helpers (OSM) for reverse / forward geocoding.
class GeocodingService {
  static const _userAgent = 'MoyStraykbol/1.0 (organizer-maps)';

  static Future<String?> reverseAddress({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': '$latitude',
        'lon': '$longitude',
        'accept-language': 'ru',
      });
      final res = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body);
      if (json is Map && json['display_name'] is String) {
        return json['display_name'] as String;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<({double lat, double lng, String label})?> searchFirst(
    String query,
  ) async {
    final q = query.trim();
    if (q.length < 2) return null;
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'jsonv2',
        'q': q,
        'limit': '1',
        'accept-language': 'ru',
      });
      final res = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body);
      if (json is! List || json.isEmpty) return null;
      final first = json.first;
      if (first is! Map) return null;
      final lat = double.tryParse('${first['lat']}');
      final lng = double.tryParse('${first['lon']}');
      if (lat == null || lng == null) return null;
      final label = '${first['display_name'] ?? q}';
      return (lat: lat, lng: lng, label: label);
    } catch (_) {
      return null;
    }
  }
}
