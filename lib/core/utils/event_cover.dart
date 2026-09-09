import 'dart:typed_data';
import 'dart:ui' as ui;

/// Canonical event cover size (16:9). Used on upload and in list/detail UI.
abstract final class EventCoverSpecs {
  static const int width = 1600;
  static const int height = 900;
  static const double aspectRatio = width / height; // 16 / 9

  /// List card fixed height (thumb = square of this size).
  static const double listCardHeight = 120;
  static const double listThumbWidth = 120;
}

/// Center-crops [bytes] to [EventCoverSpecs.aspectRatio] and scales to cover size.
Future<Uint8List> normalizeEventCoverBytes(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final src = frame.image;
  try {
    final srcW = src.width.toDouble();
    final srcH = src.height.toDouble();
    if (srcW <= 0 || srcH <= 0) return bytes;

    final targetAspect = EventCoverSpecs.aspectRatio;
    late final double cropW;
    late final double cropH;
    if (srcW / srcH > targetAspect) {
      cropH = srcH;
      cropW = srcH * targetAspect;
    } else {
      cropW = srcW;
      cropH = srcW / targetAspect;
    }
    final left = (srcW - cropW) / 2;
    final top = (srcH - cropH) / 2;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final dst = ui.Rect.fromLTWH(
      0,
      0,
      EventCoverSpecs.width.toDouble(),
      EventCoverSpecs.height.toDouble(),
    );
    canvas.drawImageRect(
      src,
      ui.Rect.fromLTWH(left, top, cropW, cropH),
      dst,
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final out = await picture.toImage(
      EventCoverSpecs.width,
      EventCoverSpecs.height,
    );
    try {
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return bytes;
      return data.buffer.asUint8List();
    } finally {
      out.dispose();
    }
  } finally {
    src.dispose();
  }
}
