bool mapkitInitialized = false;

String mapkitKeyFingerprint(String apiKey) {
  final key = apiKey.trim();
  if (key.isEmpty) return 'empty';
  if (key.length < 8) return 'len=${key.length}';
  return '${key.substring(0, 4)}…${key.substring(key.length - 4)} (len ${key.length})';
}

Future<void> initMapkitIfNeeded(String apiKey) async {
  mapkitInitialized = false;
}
