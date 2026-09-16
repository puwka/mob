import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/app_exception.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/event_cover.dart';

/// Uploads event photos to `event-images` bucket.
/// Path: `{organizerId}/{eventId}/{sort}_{ts}.jpg`
class EventImageStorageService {
  EventImageStorageService(this._client);

  final SupabaseClient _client;

  static const bucket = 'event-images';
  static const maxImagesFallback = 8;
  static const maxImages = maxImagesFallback;
  static const quality = 88;

  Future<int> resolveMaxImages() async {
    try {
      final value = await _client.rpc(
        'get_app_setting',
        params: {'p_key': 'event_images_limit'},
      );
      return int.tryParse('${value ?? ''}') ?? maxImagesFallback;
    } catch (_) {
      return maxImagesFallback;
    }
  }

  Future<Uint8List> _compress(Uint8List bytes, {required bool cover}) async {
    try {
      final source = cover ? await normalizeEventCoverBytes(bytes) : bytes;
      final out = await FlutterImageCompress.compressWithList(
        source,
        minWidth: cover ? EventCoverSpecs.width : 1600,
        minHeight: cover ? EventCoverSpecs.height : 1600,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      if (out.isEmpty) return source;
      return Uint8List.fromList(out);
    } catch (_) {
      return bytes;
    }
  }

  Future<String> uploadImage({
    required String organizerId,
    required String eventId,
    required Uint8List bytes,
    required int sortOrder,
  }) async {
    try {
      final data = await _compress(bytes, cover: sortOrder == 0);
      final fileName =
          '${sortOrder}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = '$organizerId/$eventId/$fileName';

      await _client.storage.from(bucket).uploadBinary(
            path,
            data,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
              cacheControl: '604800',
            ),
          );

      final publicUrl = _client.storage.from(bucket).getPublicUrl(path);
      return '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  /// Legacy single-cover helper (kept for callers).
  Future<String> uploadCover({
    required String organizerId,
    required String eventId,
    required Uint8List bytes,
  }) {
    return uploadImage(
      organizerId: organizerId,
      eventId: eventId,
      bytes: bytes,
      sortOrder: 0,
    );
  }

  Future<void> deleteByUrl(String url) async {
    try {
      final path = _pathFromPublicUrl(url);
      if (path == null) return;
      await _client.storage.from(bucket).remove([path]);
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  String? _pathFromPublicUrl(String url) {
    final marker = '/object/public/$bucket/';
    final idx = url.indexOf(marker);
    if (idx < 0) return null;
    var path = url.substring(idx + marker.length);
    final q = path.indexOf('?');
    if (q >= 0) path = path.substring(0, q);
    return Uri.decodeComponent(path);
  }
}
