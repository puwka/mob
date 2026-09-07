import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/app_exception.dart';
import '../core/utils/error_mapper.dart';

/// Uploads / replaces / deletes avatars in the `avatars` Storage bucket.
class AvatarStorageService {
  AvatarStorageService(this._client);

  final SupabaseClient _client;

  static const bucket = 'avatars';

  String _objectPath(String userId, String extension) =>
      '$userId/avatar.$extension';

  Future<String> uploadAvatar({
    required String userId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    try {
      final extension = _extensionFor(contentType);
      final path = _objectPath(userId, extension);

      await _client.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
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

  Future<void> deleteAvatar(String userId) async {
    try {
      final folder = await _client.storage.from(bucket).list(path: userId);
      if (folder.isEmpty) return;

      final paths = folder
          .where((f) => f.name.startsWith('avatar.'))
          .map((f) => '$userId/${f.name}')
          .toList();
      if (paths.isEmpty) return;
      await _client.storage.from(bucket).remove(paths);
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  String _extensionFor(String contentType) {
    switch (contentType) {
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'image/gif':
        return 'gif';
      default:
        return 'jpg';
    }
  }
}
