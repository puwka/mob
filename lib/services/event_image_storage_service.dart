import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/app_exception.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/event_cover.dart';

class EventImageStorageService {
  EventImageStorageService(this._client);

  final SupabaseClient _client;

  static const bucket = 'avatars';

  Future<String> uploadCover({
    required String organizerId,
    required String eventId,
    required Uint8List bytes,
  }) async {
    try {
      final normalized = await normalizeEventCoverBytes(bytes);
      final compressed = await FlutterImageCompress.compressWithList(
        normalized,
        quality: 82,
        format: CompressFormat.jpeg,
      );
      final data =
          compressed.isEmpty ? normalized : Uint8List.fromList(compressed);
      final path = '$organizerId/event_$eventId.jpg';
      await _client.storage.from(bucket).uploadBinary(
            path,
            data,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
              cacheControl: '3600',
            ),
          );
      final url = _client.storage.from(bucket).getPublicUrl(path);
      return '$url?v=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }
}
