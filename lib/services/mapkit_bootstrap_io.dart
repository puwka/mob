import 'package:flutter/foundation.dart';
import 'package:yandex_maps_mapkit_lite/init.dart' as yandex_init;
import 'package:yandex_maps_mapkit_lite/mapkit_factory.dart';

bool mapkitInitialized = false;

/// Fingerprint for logs / UI (never the full secret).
String mapkitKeyFingerprint(String apiKey) {
  final key = _sanitizeMapkitKey(apiKey);
  if (key.isEmpty) return 'empty';
  if (key.length < 8) return 'len=${key.length}';
  return '${key.substring(0, 4)}…${key.substring(key.length - 4)} (len ${key.length})';
}

String _sanitizeMapkitKey(String raw) {
  var key = raw.trim();
  // Strip BOM / zero-width / wrapping quotes from .env editors.
  key = key.replaceAll(RegExp(r'^[\uFEFF\u200B]+'), '');
  if ((key.startsWith('"') && key.endsWith('"')) ||
      (key.startsWith("'") && key.endsWith("'"))) {
    key = key.substring(1, key.length - 1).trim();
  }
  return key;
}

Future<void> initMapkitIfNeeded(String apiKey) async {
  final key = _sanitizeMapkitKey(apiKey);
  if (key.isEmpty) {
    mapkitInitialized = false;
    debugPrint(
      '[MAPKIT] YANDEX_MAPKIT_API_KEY не задан в .env — карта не инициализирована',
    );
    return;
  }
  try {
    await yandex_init.initMapkit(apiKey: key, locale: 'ru_RU');
    // Required: without onStart MapKit shows an empty grid.
    mapkit.onStart();
    mapkitInitialized = true;
    debugPrint('[MAPKIT] ok key=${mapkitKeyFingerprint(key)}');
  } catch (e, st) {
    mapkitInitialized = false;
    debugPrint('[MAPKIT] init failed key=${mapkitKeyFingerprint(key)}: $e\n$st');
  }
}
