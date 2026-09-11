import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/layout/app_layout.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../data/repositories/profile_photo_repository.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../presentation/providers/profile_providers.dart';
import '../../../presentation/providers/repository_providers.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_network_image.dart';
import '../../../widgets/feedback.dart';
import '../../../widgets/photo_lightbox.dart';

class ProfilePhotosScreen extends ConsumerStatefulWidget {
  const ProfilePhotosScreen({super.key});

  @override
  ConsumerState<ProfilePhotosScreen> createState() =>
      _ProfilePhotosScreenState();
}

class _ProfilePhotosScreenState extends ConsumerState<ProfilePhotosScreen> {
  var _busy = false;

  Future<void> _add() async {
    final photos = ref.read(myProfilePhotosProvider).valueOrNull ?? const [];
    if (photos.length >= ProfilePhotoRepository.maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Можно загрузить максимум ${ProfilePhotoRepository.maxPhotos} фото',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 88,
    );
    if (file == null) return;

    final uid = ref.read(currentUserProvider)?.id;
    if (uid == null) return;

    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      await ref.read(profilePhotoRepositoryProvider).addPhoto(
            userId: uid,
            bytes: bytes,
          );
      ref.invalidate(myProfilePhotosProvider);
      ref.invalidate(profilePhotosProvider(uid));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorMapper.map(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(String photoId, String url) async {
    final photos = ref.read(myProfilePhotosProvider).valueOrNull ?? const [];
    final photo = photos.where((p) => p.id == photoId).firstOrNull;
    if (photo == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Удалить фото?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(profilePhotoRepositoryProvider).deletePhoto(photo);
      final uid = ref.read(currentUserProvider)?.id;
      ref.invalidate(myProfilePhotosProvider);
      if (uid != null) ref.invalidate(profilePhotosProvider(uid));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorMapper.map(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myProfilePhotosProvider);
    const max = ProfilePhotoRepository.maxPhotos;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Фото'),
        actions: [
          IconButton(
            tooltip: 'Добавить',
            onPressed: _busy ? null : _add,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
          ),
        ],
      ),
      body: Stack(
        children: [
          async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: AsyncErrorRetry(
                message: ErrorMapper.map(e),
                onRetry: () => ref.invalidate(myProfilePhotosProvider),
              ),
            ),
            data: (photos) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${photos.length} / $max',
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Максимум $max фото в профиле',
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: GridView.builder(
                        itemCount: max,
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: AppLayout.gridCount(
                            context,
                            minTile: 140,
                            minCount: 2,
                            maxCount: 3,
                          ),
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 0.85,
                        ),
                        itemBuilder: (context, index) {
                          if (index < photos.length) {
                            final photo = photos[index];
                            return AppCard(
                              padding: EdgeInsets.zero,
                              onTap: () => showPhotoLightbox(
                                context,
                                urls: [for (final p in photos) p.url],
                                initialIndex: index,
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      AppRadii.card - 1,
                                    ),
                                    child: AppNetworkImage(
                                      url: photo.url,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 480,
                                      debugLabel: 'profile-gallery',
                                    ),
                                  ),
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: Material(
                                      color: AppColors.scrim,
                                      borderRadius: BorderRadius.circular(8),
                                      child: InkWell(
                                        onTap: _busy
                                            ? null
                                            : () =>
                                                _delete(photo.id, photo.url),
                                        borderRadius: BorderRadius.circular(8),
                                        child: const Padding(
                                          padding: EdgeInsets.all(6),
                                          child: Icon(
                                            Icons.delete_outline,
                                            size: 16,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          return AppCard(
                            onTap: _busy ? null : _add,
                            padding: EdgeInsets.zero,
                            child: const ColoredBox(
                              color: AppColors.surfaceElevated,
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.add,
                                      color: AppColors.accent,
                                      size: 22,
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Добавить',
                                      style: TextStyle(
                                        color: AppColors.textTertiary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          if (_busy)
            const ColoredBox(
              color: Color(0x660A0B0D),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
            ),
        ],
      ),
    );
  }
}
