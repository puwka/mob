import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/app_exception.dart';
import '../core/utils/error_mapper.dart';

/// Uploads chat videos to `chat-videos` bucket.
/// Path: `{userId}/{conversationId}/{timestamp}.{ext}`
class ChatVideoStorageService {
  ChatVideoStorageService(this._client);

  final SupabaseClient _client;

  static const bucket = 'chat-videos';
  static const maxBytes = 45 * 1024 * 1024; // under 50 MB bucket limit

  Future<String> uploadVideo({
    required String userId,
    required String conversationId,
    required Uint8List bytes,
    required String contentType,
    required String extension,
  }) async {
    try {
      if (bytes.isEmpty) {
        throw const AppException('Пустое видео');
      }
      if (bytes.length > maxBytes) {
        throw const AppException('Видео слишком большое (макс. 45 МБ)');
      }

      final safeExt = extension.replaceAll(RegExp(r'[^a-z0-9]'), '');
      final ext = safeExt.isEmpty ? 'mp4' : safeExt;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$ext';
      final path = '$userId/$conversationId/$fileName';

      await _client.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: contentType,
              cacheControl: '604800',
            ),
          );

      final publicUrl = _client.storage.from(bucket).getPublicUrl(path);
      return '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException(ErrorMapper.map(e));
    }
  }
}
