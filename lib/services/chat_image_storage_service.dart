import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/app_exception.dart';
import '../core/utils/error_mapper.dart';

/// Uploads chat images to `chat-images` bucket.
/// Path: `{userId}/{conversationId}/{timestamp}.jpg`
class ChatImageStorageService {
  ChatImageStorageService(this._client);

  final SupabaseClient _client;

  static const bucket = 'chat-images';
  static const maxEdge = 1600;
  static const quality = 82;

  Future<Uint8List> compressJpeg(Uint8List bytes) async {
    try {
      final out = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: maxEdge,
        minHeight: maxEdge,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      if (out.isEmpty) return bytes;
      return Uint8List.fromList(out);
    } catch (_) {
      return bytes;
    }
  }

  Future<String> uploadImage({
    required String userId,
    required String conversationId,
    required Uint8List bytes,
  }) async {
    try {
      final compressed = await compressJpeg(bytes);
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = '$userId/$conversationId/$fileName';

      await _client.storage.from(bucket).uploadBinary(
            path,
            compressed,
            fileOptions: const FileOptions(
              upsert: false,
              contentType: 'image/jpeg',
              cacheControl: '3600',
            ),
          );

      final publicUrl = _client.storage.from(bucket).getPublicUrl(path);
      return '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }
}
