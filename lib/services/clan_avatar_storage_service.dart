import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/app_exception.dart';
import '../core/utils/error_mapper.dart';

class ClanAvatarStorageService {
  ClanAvatarStorageService(this._client);

  final SupabaseClient _client;

  static const bucket = 'avatars';

  Future<String> uploadClanAvatar({
    required String clanId,
    required String userId,
    required Uint8List bytes,
  }) async {
    try {
      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 1024,
        minHeight: 1024,
        quality: 88,
        format: CompressFormat.jpeg,
      );
      final data = compressed.isEmpty ? bytes : Uint8List.fromList(compressed);
      final path = '$userId/clan_$clanId.jpg';
      await _client.storage.from(bucket).uploadBinary(
            path,
            data,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
              cacheControl: '604800',
            ),
          );
      final url = _client.storage.from(bucket).getPublicUrl(path);
      return '$url?v=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }
}
