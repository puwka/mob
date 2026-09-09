import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'chat_voice_recorder_io.dart'
    if (dart.library.html) 'chat_voice_recorder_web.dart' as local_file;

class VoiceCapture {
  const VoiceCapture({
    required this.bytes,
    required this.durationMs,
    required this.contentType,
    required this.extension,
  });

  final Uint8List bytes;
  final int durationMs;
  final String contentType;
  final String extension;
}

/// Cross-platform mic capture. Web uses MediaRecorder via start/stop;
/// native uses AAC file recording.
class ChatVoiceRecorder {
  ChatVoiceRecorder() : _recorder = AudioRecorder();

  final AudioRecorder _recorder;
  DateTime? _startedAt;
  String? _filePath;

  bool get isRecording => _startedAt != null;

  int get elapsedMs {
    final started = _startedAt;
    if (started == null) return 0;
    return DateTime.now().difference(started).inMilliseconds;
  }

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> start() async {
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }

    _filePath = null;
    final config = RecordConfig(
      encoder: kIsWeb ? AudioEncoder.wav : AudioEncoder.aacLc,
      bitRate: 128000,
      sampleRate: 44100,
      numChannels: 1,
    );

    if (kIsWeb) {
      // Path is ignored on web; start/stop returns a blob URL.
      await _recorder.start(config, path: 'voice.wav');
    } else {
      final dir = await getTemporaryDirectory();
      final filePath = p.join(
        dir.path,
        'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
      );
      _filePath = filePath;
      await _recorder.start(config, path: filePath);
    }
    _startedAt = DateTime.now();
  }

  Future<VoiceCapture?> stop() async {
    final started = _startedAt;
    _startedAt = null;
    final path = await _recorder.stop();
    final durationMs = started == null
        ? 0
        : DateTime.now().difference(started).inMilliseconds;

    final source = path ?? _filePath;
    _filePath = null;
    if (source == null || source.isEmpty) return null;

    final bytes = await _readBytes(source);
    if (bytes.isEmpty) return null;

    return VoiceCapture(
      bytes: bytes,
      durationMs: durationMs.clamp(0, 120000),
      contentType: kIsWeb ? 'audio/wav' : 'audio/mp4',
      extension: kIsWeb ? 'wav' : 'm4a',
    );
  }

  Future<void> cancel() async {
    _startedAt = null;
    _filePath = null;
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {}
  }

  Future<void> dispose() async {
    await cancel();
    await _recorder.dispose();
  }

  Future<Uint8List> _readBytes(String path) async {
    if (kIsWeb || path.startsWith('blob:')) {
      return local_file.readBlobUrlBytes(path);
    }
    return local_file.readLocalFileBytes(path);
  }
}
