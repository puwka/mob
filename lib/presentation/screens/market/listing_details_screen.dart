import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_layout.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../domain/models/conversation.dart';
import '../../../domain/models/listing.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../presentation/providers/chat_providers.dart';
import '../../../presentation/providers/market_providers.dart';
import '../../../presentation/providers/repository_providers.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_network_image.dart';
import '../../../widgets/feedback.dart';
import '../../../widgets/listing_card.dart';

class ListingDetailsScreen extends ConsumerStatefulWidget {
  const ListingDetailsScreen({super.key, required this.listingId});

  final String listingId;

  @override
  ConsumerState<ListingDetailsScreen> createState() =>
      _ListingDetailsScreenState();
}

class _ListingDetailsScreenState extends ConsumerState<ListingDetailsScreen> {
  int _photoIndex = 0;
  var _openingChat = false;

  Future<void> _writeSeller() async {
    if (_openingChat) return;
    setState(() => _openingChat = true);
    try {
      final id = await ref
          .read(chatRepositoryProvider)
          .openMarketChat(widget.listingId);
      if (!mounted) return;
      ref.read(chatFolderProvider.notifier).state = ConversationType.market;
      context.go('/main/chats/$id');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorMapper.map(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(listingDetailsProvider(widget.listingId));
    final userId = ref.watch(authRepositoryProvider).currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Объявление'),
        actions: [
          async.maybeWhen(
            data: (listing) {
              final isOwner = userId != null && listing.sellerId == userId;
              if (!isOwner) {
                return IconButton(
                  tooltip: 'Избранное',
                  onPressed: () => ref
                      .read(listingDetailsProvider(widget.listingId).notifier)
                      .toggleFavorite(),
                  icon: Icon(
                    listing.isFavorite ? Icons.favorite : Icons.favorite_border,
                    size: 18,
                    color: listing.isFavorite
                        ? AppColors.danger
                        : AppColors.textSecondary,
                  ),
                );
              }
              return IconButton(
                tooltip: 'Редактировать',
                onPressed: () =>
                    context.push('/main/market/${listing.id}/edit'),
                icon: const Icon(Icons.edit_outlined, size: 18),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncErrorRetry(
          message: ErrorMapper.map(e),
          onRetry: () => ref
              .read(listingDetailsProvider(widget.listingId).notifier)
              .refresh(),
        ),
        data: (listing) {
          final images = listing.images;
          final cover = images.isEmpty
              ? null
              : images[_photoIndex.clamp(0, images.length - 1)].url;
          final isOwner = userId != null && listing.sellerId == userId;
          final heroH = AppLayout.listingHeroHeight(context);

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    ColoredBox(
                      color: AppColors.surfaceElevated,
                      child: SizedBox(
                        width: double.infinity,
                        height: heroH,
                        child: cover == null
                            ? const Icon(
                                Icons.image_outlined,
                                color: AppColors.textTertiary,
                                size: 36,
                              )
                            : AppNetworkImage(
                                url: cover,
                                fit: BoxFit.contain,
                                width: double.infinity,
                                height: heroH,
                                memCacheWidth: 1200,
                                debugLabel: 'listing-detail',
                              ),
                      ),
                    ),
                    if (images.length > 1)
                      SizedBox(
                        height: 64,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          itemCount: images.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 6),
                          itemBuilder: (context, index) {
                            final selected = index == _photoIndex;
                            return GestureDetector(
                              onTap: () => setState(() => _photoIndex = index),
                              child: Container(
                                width: 64,
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(AppRadii.badge),
                                  border: Border.all(
                                    color: selected
                                        ? AppColors.accent
                                        : AppColors.border,
                                    width: selected ? 1.4 : 1,
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: AppNetworkImage(
                                  url: images[index].url,
                                  fit: BoxFit.cover,
                                  width: 64,
                                  height: 64,
                                  memCacheWidth: 160,
                                  debugLabel: 'listing-thumb',
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            listing.title,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(fontSize: 20),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            listing.priceLabel,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  color: AppColors.accent,
                                  fontSize: 22,
                                ),
                          ),
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: listing.sellerId.isNotEmpty
                                ? () => context.push(
                                      '/main/profile/user/${listing.sellerId}',
                                    )
                                : null,
                            child: _MetaRow(
                              icon: Icons.person_outline,
                              text: listing.sellerNickname ?? 'Продавец',
                            ),
                          ),
                          const SizedBox(height: 4),
                          _MetaRow(
                            icon: Icons.location_on_outlined,
                            text: listing.city,
                          ),
                          const SizedBox(height: 4),
                          _MetaRow(
                            icon: Icons.category_outlined,
                            text: listing.shortSpecs,
                          ),
                          const SizedBox(height: 4),
                          _MetaRow(
                            icon: Icons.calendar_today_outlined,
                            text: formatListingDate(listing.createdAt),
                          ),
                          const SizedBox(height: 4),
                          _MetaRow(
                            icon: Icons.visibility_outlined,
                            text: '${listing.viewsCount} просмотров',
                          ),
                          if (listing.status != ListingStatus.active) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Статус: ${listing.status.labelRu}',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(color: AppColors.warning),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Text(
                            'ОПИСАНИЕ',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: AppColors.accent,
                                  letterSpacing: 0.9,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            listing.description,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'ХАРАКТЕРИСТИКИ',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: AppColors.accent,
                                  letterSpacing: 0.9,
                                ),
                          ),
                          const SizedBox(height: 8),
                          _SpecLine(
                            label: 'Категория',
                            value: listing.parentCategoryName ??
                                listing.categoryName ??
                                '—',
                          ),
                          if (listing.parentCategoryName != null &&
                              listing.categoryName != null)
                            _SpecLine(
                              label: 'Подкатегория',
                              value: listing.categoryName!,
                            ),
                          _SpecLine(
                            label: 'Состояние',
                            value: listing.condition.labelRu,
                          ),
                          _SpecLine(label: 'Город', value: listing.city),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (!isOwner)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: AppButton(
                      label: 'Написать',
                      icon: Icons.chat_bubble_outline,
                      loading: _openingChat,
                      onPressed: _openingChat ? null : _writeSeller,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.textTertiary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                ),
          ),
        ),
      ],
    );
  }
}

class _SpecLine extends StatelessWidget {
  const _SpecLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
