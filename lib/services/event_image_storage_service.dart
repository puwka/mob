import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/app_exception.dart';
import '../core/utils/error_mapper.dart';

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
      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 1280,
        minHeight: 720,
        quality: 82,
        format: CompressFormat.jpeg,
      );
      final data = compressed.isEmpty ? bytes : Uint8List.fromList(compressed);
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
