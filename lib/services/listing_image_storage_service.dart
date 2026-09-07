import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/app_exception.dart';
import '../core/utils/error_mapper.dart';

/// Uploads listing photos to `listing-images` bucket.
/// Path: `{userId}/{listingId}/{fileName}`
class ListingImageStorageService {
  ListingImageStorageService(this._client);

  final SupabaseClient _client;

  static const bucket = 'listing-images';
  static const maxImagesFallback = 8;
  static const maxImages = maxImagesFallback;
  static const maxEdge = 1280;
  static const quality = 78;

  Future<int> resolveMaxImages() async {
    try {
      final value = await _client.rpc(
        'get_app_setting',
        params: {'p_key': 'listing_images_limit'},
      );
      return int.tryParse('${value ?? ''}') ?? maxImagesFallback;
    } catch (_) {
      return maxImagesFallback;
    }
  }

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
    required String listingId,
    required Uint8List bytes,
    required int sortOrder,
  }) async {
    try {
      final compressed = await compressJpeg(bytes);
      final fileName =
          '${sortOrder}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = '$userId/$listingId/$fileName';

      await _client.storage.from(bucket).uploadBinary(
            path,
            compressed,
            fileOptions: const FileOptions(
              upsert: true,
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

  Future<void> deleteByUrl(String url) async {
    try {
      final path = _pathFromPublicUrl(url);
      if (path == null) return;
      await _client.storage.from(bucket).remove([path]);
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<void> deleteListingFolder({
    required String userId,
    required String listingId,
  }) async {
    try {
      final folder =
          await _client.storage.from(bucket).list(path: '$userId/$listingId');
      if (folder.isEmpty) return;
      final paths =
          folder.map((f) => '$userId/$listingId/${f.name}').toList();
      await _client.storage.from(bucket).remove(paths);
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
