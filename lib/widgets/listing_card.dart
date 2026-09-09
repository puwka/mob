import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_colors.dart';
import '../domain/models/listing.dart';
import 'app_network_image.dart';

/// Compact listing row: image left, info right, favorite top-right.
class ListingCard extends StatelessWidget {
  const ListingCard({
    super.key,
    required this.listing,
    required this.onTap,
    this.onFavorite,
  });

  final Listing listing;
  final VoidCallback onTap;
  final VoidCallback? onFavorite;

  @override
  Widget build(BuildContext context) {
    final cover = listing.coverUrl;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Container(
          decoration: BoxDecoration(
            color: listing.isPromotionActive
                ? AppColors.accentSoft
                : AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(
              color: listing.isPromotionActive
                  ? AppColors.accent
                  : AppColors.border,
              width: listing.isPromotionActive ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: 104,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 96,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AppNetworkImage(
                        url: cover,
                        fit: BoxFit.cover,
                        width: 96,
                        height: 104,
                        memCacheWidth: 240,
                        memCacheHeight: 260,
                        debugLabel: 'listing-cover',
                      ),
                      if (listing.isPromotionActive)
                        Positioned(
                          left: 6,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'ТОП',
                              style: TextStyle(
                                color: AppColors.background,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 34, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              listing.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontSize: 14.5),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              listing.priceLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: AppColors.accent,
                                    fontSize: 14,
                                  ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              listing.city,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(fontSize: 11.5),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              listing.shortSpecs,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    fontSize: 11.5,
                                    color: AppColors.textTertiary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      if (onFavorite != null)
                        Positioned(
                          top: 2,
                          right: 2,
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            onPressed: onFavorite,
                            icon: Icon(
                              listing.isFavorite
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              size: 18,
                              color: listing.isFavorite
                                  ? AppColors.danger
                                  : AppColors.textTertiary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String formatListingDate(DateTime date) {
  return DateFormat('d MMM yyyy', 'ru').format(date.toLocal());
}
