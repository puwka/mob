import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/listing.dart';
import 'auth_providers.dart';
import 'repository_providers.dart';

final listingFiltersProvider =
    StateNotifierProvider<ListingFiltersNotifier, ListingFilters>((ref) {
  return ListingFiltersNotifier(const ListingFilters());
});

class ListingFiltersNotifier extends StateNotifier<ListingFilters> {
  ListingFiltersNotifier(super.state);

  void setQuery(String query) {
    if (state.query == query) return;
    state = state.copyWith(query: query);
  }

  void setCity(String? city) {
    if (state.city == city) return;
    state = state.copyWith(city: city, clearCity: city == null);
  }

  void setCategory(String? categoryId) {
    if (state.categoryId == categoryId && state.subcategoryId == null) return;
    state = state.copyWith(
      categoryId: categoryId,
      clearCategory: categoryId == null,
      clearSubcategory: true,
    );
  }

  void setSubcategory(String? subcategoryId) {
    if (state.subcategoryId == subcategoryId) return;
    state = state.copyWith(
      subcategoryId: subcategoryId,
      clearSubcategory: subcategoryId == null,
    );
  }

  void setSort(ListingSort sort) {
    if (state.sort == sort) return;
    state = state.copyWith(sort: sort);
  }

  void apply(ListingFilters filters) => state = filters;

  void reset({String? keepCity}) {
    state = ListingFilters(city: keepCity);
  }
}

final marketCategoriesProvider =
    FutureProvider<List<MarketCategory>>((ref) async {
  return ref.read(listingRepositoryProvider).fetchCategories();
});

final marketListingsProvider =
    AsyncNotifierProvider<MarketListingsNotifier, List<Listing>>(
  MarketListingsNotifier.new,
);

class MarketListingsNotifier extends AsyncNotifier<List<Listing>> {
  @override
  Future<List<Listing>> build() async {
    final filters = ref.watch(listingFiltersProvider);

    // Soft-load categories — never block the feed on category errors.
    var categories = const <MarketCategory>[];
    try {
      categories = await ref.read(listingRepositoryProvider).fetchCategories();
    } catch (_) {}

    return _fetch(filters, categories);
  }

  Future<List<Listing>> _fetch(
    ListingFilters filters,
    List<MarketCategory> categories,
  ) async {
    final repo = ref.read(listingRepositoryProvider);

    late final List<Listing> list;
    if (filters.subcategoryId != null) {
      list = await repo.fetchListings(filters);
    } else if (filters.categoryId != null) {
      final ids = <String>[filters.categoryId!];
      for (final c in categories) {
        if (c.parentId == filters.categoryId) ids.add(c.id);
      }
      list = await repo.fetchListingsInCategories(filters, categoryIds: ids);
    } else {
      list = await repo.fetchListings(filters);
    }
    return _enrichParents(list, categories);
  }

  List<Listing> _enrichParents(
    List<Listing> list,
    List<MarketCategory> categories,
  ) {
    if (categories.isEmpty) return list;
    final byId = {for (final c in categories) c.id: c};
    return [
      for (final item in list)
        () {
          final cat = byId[item.categoryId];
          if (cat == null) return item;
          final parent = cat.parentId == null ? null : byId[cat.parentId!];
          return item.copyWith(
            categoryName: item.categoryName ?? cat.name,
            parentCategoryName: parent?.name ?? item.parentCategoryName,
          );
        }(),
    ];
  }

  Future<void> refresh({bool silent = false}) async {
    final filters = ref.read(listingFiltersProvider);
    var categories = const <MarketCategory>[];
    try {
      categories = await ref.read(listingRepositoryProvider).fetchCategories();
    } catch (_) {}
    if (!silent) state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetch(filters, categories));
  }

  Future<void> toggleFavorite(String listingId) async {
    final next =
        await ref.read(listingRepositoryProvider).toggleFavorite(listingId);
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData([
      for (final item in current)
        if (item.id == listingId) item.copyWith(isFavorite: next) else item,
    ]);
  }
}

final listingDetailsProvider =
    AsyncNotifierProvider.family<ListingDetailsNotifier, Listing, String>(
  ListingDetailsNotifier.new,
);

class ListingDetailsNotifier extends FamilyAsyncNotifier<Listing, String> {
  var _viewsCounted = false;

  @override
  Future<Listing> build(String arg) async {
    final listing = await ref.read(listingRepositoryProvider).fetchById(arg);
    if (!_viewsCounted) {
      _viewsCounted = true;
      ref.read(listingRepositoryProvider).incrementViews(arg);
    }
    return listing;
  }

  Future<void> refresh({bool silent = false}) async {
    if (!silent) state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(listingRepositoryProvider).fetchById(arg),
    );
  }

  Future<void> toggleFavorite() async {
    final next =
        await ref.read(listingRepositoryProvider).toggleFavorite(arg);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(isFavorite: next));
    }
    await ref.read(marketListingsProvider.notifier).refresh(silent: true);
  }
}

final myListingsStatusFilterProvider =
    StateProvider<ListingStatus?>((ref) => ListingStatus.active);

final myListingsProvider =
    AsyncNotifierProvider<MyListingsNotifier, List<Listing>>(
  MyListingsNotifier.new,
);

class MyListingsNotifier extends AsyncNotifier<List<Listing>> {
  @override
  Future<List<Listing>> build() async {
    final status = ref.watch(myListingsStatusFilterProvider);
    return ref.read(listingRepositoryProvider).fetchMyListings(status: status);
  }

  Future<void> refresh({bool silent = false}) async {
    final status = ref.read(myListingsStatusFilterProvider);
    if (!silent) state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(listingRepositoryProvider).fetchMyListings(status: status),
    );
  }

  Future<void> setStatus(String id, ListingStatus status) async {
    await ref.read(listingRepositoryProvider).setStatus(id, status);
    await refresh(silent: true);
    await ref.read(marketListingsProvider.notifier).refresh(silent: true);
  }

  Future<void> delete(String id) async {
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    await ref.read(listingRepositoryProvider).deleteListing(id);
    if (userId != null) {
      try {
        await ref
            .read(listingImageStorageServiceProvider)
            .deleteListingFolder(userId: userId, listingId: id);
      } catch (_) {}
    }
    await refresh(silent: true);
    await ref.read(marketListingsProvider.notifier).refresh(silent: true);
  }
}
