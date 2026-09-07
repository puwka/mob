import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../domain/models/listing.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../presentation/providers/market_providers.dart';
import '../../../widgets/feedback.dart';
import '../../../widgets/listing_card.dart';
import '../../../widgets/market_filter_sheet.dart';

class MarketScreen extends ConsumerStatefulWidget {
  const MarketScreen({super.key});

  @override
  ConsumerState<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends ConsumerState<MarketScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  var _showAllCategories = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      ref.read(listingFiltersProvider.notifier).setQuery(value);
    });
  }

  Future<void> _openFilters(ListingFilters filters) async {
    final categories =
        ref.read(marketCategoriesProvider).valueOrNull ?? const <MarketCategory>[];
    final profileCity = ref.read(currentProfileProvider).valueOrNull?.city;

    // Prefill city for the sheet only — do not mutate filters during build/nav.
    final seed = (filters.city == null || filters.city!.isEmpty) &&
            profileCity != null &&
            profileCity.isNotEmpty
        ? filters.copyWith(city: profileCity)
        : filters;

    final next = await showMarketFilterSheet(
      context,
      current: seed,
      categories: categories,
    );
    if (!mounted || next == null) return;
    ref.read(listingFiltersProvider.notifier).apply(next);
    _search.text = next.query;
  }

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(listingFiltersProvider);
    final listingsAsync = ref.watch(marketListingsProvider);
    final categoriesAsync = ref.watch(marketCategoriesProvider);
    final profileCity = ref.watch(currentProfileProvider).valueOrNull?.city;

    final cityLabel = (filters.city != null && filters.city!.isNotEmpty)
        ? filters.city!
        : (profileCity != null && profileCity.isNotEmpty ? profileCity : 'все');

    final roots =
        categoriesAsync.valueOrNull?.where((c) => c.isRoot).toList() ??
            const <MarketCategory>[];
    final visibleRoots = _showAllCategories ? roots : roots.take(5).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Барахолка',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontSize: 18,
                          ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push('/main/market/my'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Мои'),
                  ),
                  const SizedBox(width: 4),
                  Material(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(AppRadii.button),
                    child: InkWell(
                      onTap: () => context.push('/main/market/create'),
                      borderRadius: BorderRadius.circular(AppRadii.button),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          '+ Создать',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF121408),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openFilters(filters),
                child: Text(
                  'Город: $cityLabel',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: TextField(
                        controller: _search,
                        onChanged: _onSearchChanged,
                        style: const TextStyle(fontSize: 14.5),
                        cursorColor: AppColors.accent,
                        decoration: const InputDecoration(
                          hintText: 'Поиск по товарам',
                          prefixIcon: Icon(
                            Icons.search,
                            size: 18,
                            color: AppColors.textTertiary,
                          ),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(AppRadii.button),
                    child: InkWell(
                      onTap: () => _openFilters(filters),
                      borderRadius: BorderRadius.circular(AppRadii.button),
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadii.button),
                          border: Border.all(
                            color: filters.hasActiveFilters
                                ? AppColors.accentDim
                                : AppColors.border,
                          ),
                        ),
                        child: Icon(
                          Icons.tune,
                          size: 18,
                          color: filters.hasActiveFilters
                              ? AppColors.accent
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 1 +
                    visibleRoots.length +
                    (roots.length > 5 ? 1 : 0),
                separatorBuilder: (context, index) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _CatChip(
                      label: 'Все',
                      selected: filters.categoryId == null,
                      onTap: () => ref
                          .read(listingFiltersProvider.notifier)
                          .setCategory(null),
                    );
                  }
                  final rootIndex = index - 1;
                  if (rootIndex < visibleRoots.length) {
                    final c = visibleRoots[rootIndex];
                    return _CatChip(
                      label: c.name,
                      selected: filters.categoryId == c.id,
                      onTap: () => ref
                          .read(listingFiltersProvider.notifier)
                          .setCategory(c.id),
                    );
                  }
                  return _CatChip(
                    label: _showAllCategories ? 'Свернуть' : 'Еще',
                    selected: false,
                    onTap: () => setState(
                      () => _showAllCategories = !_showAllCategories,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: listingsAsync.when(
                loading: () => const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (e, _) => Center(
                  child: AsyncErrorRetry(
                    message: ErrorMapper.map(e),
                    onRetry: () =>
                        ref.read(marketListingsProvider.notifier).refresh(),
                  ),
                ),
                data: (listings) {
                  if (listings.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: const [
                        SizedBox(height: 48),
                        EmptyStateCard(
                          title: 'Объявлений не найдено',
                          subtitle:
                              'Измените фильтры или создайте первое объявление.',
                          icon: Icons.storefront_outlined,
                        ),
                      ],
                    );
                  }
                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    itemCount: listings.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = listings[index];
                      return ListingCard(
                        listing: item,
                        onTap: () => context.push('/main/market/${item.id}'),
                        onFavorite: () => ref
                            .read(marketListingsProvider.notifier)
                            .toggleFavorite(item.id),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatChip extends StatelessWidget {
  const _CatChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accentSoft : AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(AppRadii.chip),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.chip),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
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
      ),
    );
  }
}
