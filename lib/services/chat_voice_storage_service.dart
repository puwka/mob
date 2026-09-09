import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/app_exception.dart';
import '../core/utils/error_mapper.dart';

/// Uploads voice clips to `chat-voice` bucket.
/// Path: `{userId}/{conversationId}/{timestamp}.{ext}`
class ChatVoiceStorageService {
  ChatVoiceStorageService(this._client);

  final SupabaseClient _client;

  static const bucket = 'chat-voice';

  Future<String> uploadVoice({
    required String userId,
    required String conversationId,
    required Uint8List bytes,
    required String contentType,
    required String extension,
  }) async {
    try {
      final safeExt = extension.replaceAll(RegExp(r'[^a-z0-9]'), '');
      final ext = safeExt.isEmpty ? 'm4a' : safeExt;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$ext';
      final path = '$userId/$conversationId/$fileName';

      await _client.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: contentType,
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
