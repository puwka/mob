import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/app_exception.dart';
import '../../core/utils/error_mapper.dart';
import '../../domain/models/profile_photo.dart';

class ProfilePhotoRepository {
  ProfilePhotoRepository(this._client);

  final SupabaseClient _client;

  static const maxPhotosFallback = 6;
  static const bucket = 'avatars';

  Future<int> resolveMaxPhotos() async {
    try {
      final value = await _client.rpc(
        'get_app_setting',
        params: {'p_key': 'profile_photos_limit'},
      );
      return int.tryParse('${value ?? ''}') ?? maxPhotosFallback;
    } catch (_) {
      return maxPhotosFallback;
    }
  }

  /// Kept for call sites; prefer [resolveMaxPhotos] when checking before upload.
  static const maxPhotos = maxPhotosFallback;

  Future<List<ProfilePhoto>> fetchForUser(String userId) async {
    try {
      final rows = await _client
          .from('profile_photos')
          .select()
          .eq('user_id', userId)
          .order('sort_order', ascending: true)
          .timeout(const Duration(seconds: 12));

      return [
        for (final raw in rows as List)
          ProfilePhoto.fromJson(Map<String, dynamic>.from(raw as Map)),
      ];
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<ProfilePhoto> addPhoto({
    required String userId,
    required Uint8List bytes,
  }) async {
    try {
      final existing = await fetchForUser(userId);
      final limit = await resolveMaxPhotos();
      if (existing.length >= limit) {
        throw AppException('Можно загрузить максимум $limit фото');
      }

      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 1600,
        minHeight: 1600,
        quality: 88,
        format: CompressFormat.jpeg,
      );
      final data = compressed.isEmpty ? bytes : Uint8List.fromList(compressed);

      final fileName =
          'gallery_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = '$userId/$fileName';

      await _client.storage.from(bucket).uploadBinary(
            path,
            data,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
              cacheControl: '604800',
            ),
          );

      final url =
          '${_client.storage.from(bucket).getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';

      final id = await _client.rpc(
        'add_profile_photo',
        params: {'p_url': url},
      );

      return ProfilePhoto(
        id: id as String,
        userId: userId,
        url: url,
        sortOrder: existing.length,
      );
    } catch (e) {
      if (e is AppException) rethrow;
      final msg = e.toString().toUpperCase();
      if (msg.contains('PHOTO_LIMIT')) {
        throw AppException(
          'Можно загрузить максимум $maxPhotosFallback фото',
        );
      }
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<void> deletePhoto(ProfilePhoto photo) async {
    try {
      await _client.rpc(
        'delete_profile_photo',
        params: {'p_photo_id': photo.id},
      );

      // Best-effort storage cleanup
      try {
        final uri = Uri.parse(photo.url.split('?').first);
        final segments = uri.pathSegments;
        final idx = segments.indexOf(bucket);
        if (idx >= 0 && idx + 1 < segments.length) {
          final objectPath = segments.sublist(idx + 1).join('/');
          await _client.storage.from(bucket).remove([objectPath]);
        }
      } catch (_) {}
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }
}
