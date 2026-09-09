import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Lightweight timing logs for API / storage work during development.
abstract final class PerfLog {
  static Future<T> time<T>(
    String label,
    Future<T> Function() run, {
    String channel = 'API',
  }) async {
    final sw = Stopwatch()..start();
    try {
      return await run();
    } finally {
      sw.stop();
      final ms = sw.elapsedMilliseconds;
      final line = '$label — ${ms}ms';
      if (ms >= 1000) {
        developer.log('SLOW REQUEST: $line', name: channel, level: 900);
        if (kDebugMode) debugPrint('[$channel] SLOW REQUEST: $line');
      } else if (kDebugMode) {
        debugPrint('[$channel] $line');
      }
    }
  }
}
