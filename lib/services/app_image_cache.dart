import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Shared disk cache for network images — long retention, high capacity.
abstract final class AppImageCache {
  static const _key = 'tactical_images_v1';

  static final CacheManager manager = CacheManager(
    Config(
      _key,
      stalePeriod: const Duration(days: 45),
      maxNrOfCacheObjects: 1200,
    ),
  );

  /// Warm disk cache in parallel (best-effort).
  static Future<void> prefetch(
    Iterable<String?> urls, {
    int limit = 24,
  }) async {
    final seen = <String>{};
    final jobs = <Future<void>>[];
    for (final raw in urls) {
      if (jobs.length >= limit) break;
      final url = raw?.trim();
      if (url == null || url.isEmpty || !seen.add(url)) continue;
      jobs.add(_downloadQuiet(url));
    }
    if (jobs.isEmpty) return;
    await Future.wait(jobs);
  }

  static Future<void> _downloadQuiet(String url) async {
    try {
      await manager.downloadFile(url);
    } catch (_) {}
  }
}
