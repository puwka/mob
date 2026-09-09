import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../domain/models/listing.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../presentation/providers/market_providers.dart';
import '../../../presentation/providers/repository_providers.dart';
import '../../../services/listing_image_storage_service.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_text_field.dart';
import '../../../widgets/city_picker.dart';
import '../../../widgets/feedback.dart';

class CreateListingScreen extends ConsumerStatefulWidget {
  const CreateListingScreen({super.key, this.listingId});

  final String? listingId;

  bool get isEdit => listingId != null;

  @override
  ConsumerState<CreateListingScreen> createState() =>
      _CreateListingScreenState();
}

class _LocalImage {
  _LocalImage({required this.bytes, this.existing});

  final Uint8List bytes;
  final ListingImage? existing;
}

class _CreateListingScreenState extends ConsumerState<CreateListingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _city = TextEditingController();

  String? _rootCategoryId;
  String? _subCategoryId;
  ListingCondition _condition = ListingCondition.used;
  final List<_LocalImage> _images = [];
  final List<ListingImage> _removedExisting = [];

  bool _loading = false;
  bool _bootstrapped = false;
  String? _formError;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _bootstrapEdit(Listing listing) async {
    if (_bootstrapped) return;
    _bootstrapped = true;
    _title.text = listing.title;
    _description.text = listing.description;
    _price.text = listing.price.toStringAsFixed(0);
    _city.text = listing.city;
    _condition = listing.condition;

    final categories = await ref.read(marketCategoriesProvider.future);
    final matches = categories.where((c) => c.id == listing.categoryId);
    final cat = matches.isEmpty ? null : matches.first;
    if (cat != null) {
      if (cat.parentId == null) {
        _rootCategoryId = cat.id;
      } else {
        _rootCategoryId = cat.parentId;
        _subCategoryId = cat.id;
      }
    }

    for (final img in listing.images) {
      _images.add(_LocalImage(bytes: Uint8List(0), existing: img));
    }
    setState(() {});
  }

  Future<void> _pickImages() async {
    final left = ListingImageStorageService.maxImages - _images.length;
    if (left <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Максимум ${ListingImageStorageService.maxImages} фото'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final picker = ImagePicker();
    final files = await picker.pickMultiImage(imageQuality: 90);
    if (files.isEmpty) return;

    for (final file in files.take(left)) {
      final bytes = await file.readAsBytes();
      setState(() => _images.add(_LocalImage(bytes: bytes)));
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _formError = null);
    if (!_formKey.currentState!.validate()) return;

    final categoryId = _subCategoryId ?? _rootCategoryId;
    if (categoryId == null) {
      setState(() => _formError = 'Выберите категорию');
      return;
    }
    if (_images.isEmpty) {
      setState(() => _formError = 'Добавьте хотя бы одно фото');
      return;
    }

    final price = double.tryParse(_price.text.replaceAll(' ', '').replaceAll(',', '.'));
    if (price == null || price < 0) {
      setState(() => _formError = 'Укажите корректную цену');
      return;
    }

    setState(() => _loading = true);
    try {
      final repo = ref.read(listingRepositoryProvider);
      final storage = ref.read(listingImageStorageServiceProvider);
      final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
      if (userId == null) throw const FormatException('auth');

      late Listing listing;
      if (widget.isEdit) {
        listing = await repo.updateListing(
          id: widget.listingId!,
          categoryId: categoryId,
          title: _title.text,
          description: _description.text,
          price: price,
          city: _city.text,
          condition: _condition,
        );

        for (final removed in _removedExisting) {
          await repo.deleteImage(removed.id);
          try {
            await storage.deleteByUrl(removed.url);
          } catch (_) {}
        }
      } else {
        listing = await repo.createListing(
          categoryId: categoryId,
          title: _title.text,
          description: _description.text,
          price: price,
          city: _city.text,
          condition: _condition,
          status: ListingStatus.pending,
        );
      }

      var order = 0;
      for (final img in _images) {
        if (img.existing != null) {
          order++;
          continue;
        }
        final url = await storage.uploadImage(
          userId: userId,
          listingId: listing.id,
          bytes: img.bytes,
          sortOrder: order,
        );
        await repo.addImage(
          listingId: listing.id,
          url: url,
          sortOrder: order,
        );
        order++;
      }

      // Persist order for existing+new sequence
      final refreshed = await repo.fetchById(listing.id);
      await repo.reorderImages(refreshed.images);

      await ref.read(marketListingsProvider.notifier).refresh(silent: true);
      await ref.read(myListingsProvider.notifier).refresh(silent: true);

      if (!mounted) return;
      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isEdit ? 'Объявление обновлено' : 'Отправлено на модерацию'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      setState(() => _formError = ErrorMapper.map(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(marketCategoriesProvider);
    final profileCity = ref.watch(currentProfileProvider).valueOrNull?.city;

    if (!widget.isEdit && _city.text.isEmpty && profileCity != null) {
      _city.text = profileCity;
    }

    if (widget.isEdit) {
      final details = ref.watch(listingDetailsProvider(widget.listingId!));
      details.whenData(_bootstrapEdit);
    }

    final categories = categoriesAsync.valueOrNull ?? const <MarketCategory>[];
    final roots = categories.where((c) => c.isRoot).toList();
    final subs = categories
        .where((c) => c.parentId == _rootCategoryId)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit ? 'Редактирование' : 'Новое объявление'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(
                'Фотографии',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 88,
                child: ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  buildDefaultDragHandles: false,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = _images.removeAt(oldIndex);
                      _images.insert(newIndex, item);
                    });
                  },
                  itemCount: _images.length + 1,
                  itemBuilder: (context, index) {
                    if (index == _images.length) {
                      return Padding(
                        key: const ValueKey('add'),
                        padding: const EdgeInsets.only(right: 8),
                        child: InkWell(
                          onTap: _loading ? null : _pickImages,
                          borderRadius: BorderRadius.circular(AppRadii.badge),
                          child: Container(
                            width: 88,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius:
                                  BorderRadius.circular(AppRadii.badge),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: const Icon(
                              Icons.add_photo_alternate_outlined,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                      );
                    }

                    final img = _images[index];
                    return Padding(
                      key: ValueKey(img.existing?.id ?? 'local-$index-${img.bytes.length}'),
                      padding: const EdgeInsets.only(right: 8),
                      child: Stack(
                        children: [
                          ReorderableDelayedDragStartListener(
                            index: index,
                            child: ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(AppRadii.badge),
                              child: SizedBox(
                                width: 88,
                                height: 88,
                                child: img.existing != null
                                    ? Image.network(
                                        img.existing!.url,
                                        fit: BoxFit.cover,
                                      )
                                    : Image.memory(
                                        img.bytes,
                                        fit: BoxFit.cover,
                                      ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: InkWell(
                              onTap: _loading
                                  ? null
                                  : () => setState(() {
                                        final removed = _images.removeAt(index);
                                        if (removed.existing != null) {
                                          _removedExisting
                                              .add(removed.existing!);
                                        }
                                      }),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: AppColors.scrim,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'До ${ListingImageStorageService.maxImages} фото · удерживайте для сортировки',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              AppTextField(
                controller: _title,
                label: 'Название',
                hint: 'Например, AEG M4 Cyma',
                textInputAction: TextInputAction.next,
                validator: (v) {
                  if (v == null || v.trim().length < 3) {
                    return 'Минимум 3 символа';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _description,
                label: 'Описание',
                hint: 'Состояние, комплектация, нюансы',
                maxLines: 4,
                minLines: 3,
                validator: (v) {
                  if (v == null || v.trim().length < 10) {
                    return 'Опишите товар подробнее';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _price,
                label: 'Цена, ₽',
                hint: '0',
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = double.tryParse(
                    (v ?? '').replaceAll(' ', '').replaceAll(',', '.'),
                  );
                  if (n == null || n < 0) return 'Укажите цену';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Text('Категория', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in roots)
                    _SelectChip(
                      label: c.name,
                      selected: _rootCategoryId == c.id,
                      onTap: () => setState(() {
                        _rootCategoryId = c.id;
                        _subCategoryId = null;
                      }),
                    ),
                ],
              ),
              if (subs.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Подкатегория',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in subs)
                      _SelectChip(
                        label: c.name,
                        selected: _subCategoryId == c.id,
                        onTap: () => setState(() => _subCategoryId = c.id),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Text('Состояние', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in ListingCondition.values)
                    _SelectChip(
                      label: c.labelRu,
                      selected: _condition == c,
                      onTap: () => setState(() => _condition = c),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _city,
                label: 'Город',
                hint: 'Выберите город',
                readOnly: true,
                prefixIcon: Icons.location_city_outlined,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Выберите город' : null,
                onTap: _loading
                    ? null
                    : () async {
                        final city = await showCityPicker(
                          context,
                          selected: _city.text,
                        );
                        if (city != null) setState(() => _city.text = city);
                      },
                suffix: const Icon(
                  Icons.expand_more,
                  color: AppColors.textTertiary,
                ),
              ),
              if (_formError != null) ...[
                const SizedBox(height: 12),
                ErrorBanner(message: _formError!),
              ],
              const SizedBox(height: 18),
              AppButton(
                label: widget.isEdit ? 'Сохранить' : 'Отправить на модерацию',
                loading: _loading,
                onPressed: _loading ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectChip extends StatelessWidget {
  const _SelectChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadii.chip),
          border: Border.all(
            color: selected ? AppColors.accentDim : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
