import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/app_exception.dart';
import '../../core/utils/error_mapper.dart';
import '../../domain/models/listing.dart';

class ListingRepository {
  ListingRepository(this._client);

  final SupabaseClient _client;

  static const _selectLite = '''
    id,
    seller_id,
    category_id,
    title,
    description,
    price,
    city,
    condition,
    status,
    views_count,
    is_promoted,
    promoted_until,
    created_at,
    updated_at
  ''';

  Future<List<MarketCategory>> fetchCategories() async {
    try {
      final rows = await _client
          .from('categories')
          .select('id, name, parent_id, icon, sort_order, created_at')
          .order('sort_order', ascending: true)
          .timeout(const Duration(seconds: 15));
      return (rows as List)
          .map((e) => MarketCategory.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<List<Listing>> fetchListings(ListingFilters filters) async {
    try {
      final rows = await _runFeedQuery(
        filters: filters,
        categoryIds: null,
      );
      final list = _mapRows(rows);
      return _attachImagesAndFavorites(list);
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  /// Fetch active listings for a root category including all subcategories.
  Future<List<Listing>> fetchListingsInCategories(
    ListingFilters filters, {
    required List<String> categoryIds,
  }) async {
    try {
      if (categoryIds.isEmpty) {
        return fetchListings(filters);
      }
      final rows = await _runFeedQuery(
        filters: filters,
        categoryIds: categoryIds,
      );
      final list = _mapRows(rows);
      return _attachImagesAndFavorites(list);
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<dynamic> _runFeedQuery({
    required ListingFilters filters,
    required List<String>? categoryIds,
  }) async {
    return _executeFeed(
      select: _selectLite,
      filters: filters,
      categoryIds: categoryIds,
    ).timeout(const Duration(seconds: 20));
  }

  Future<dynamic> _executeFeed({
    required String select,
    required ListingFilters filters,
    required List<String>? categoryIds,
  }) {
    var query = _client.from('listings').select(select).eq('status', 'active');

    if (categoryIds != null && categoryIds.isNotEmpty) {
      query = query.inFilter('category_id', categoryIds);
    } else if (filters.subcategoryId != null) {
      query = query.eq('category_id', filters.subcategoryId!);
    } else if (filters.categoryId != null) {
      query = query.eq('category_id', filters.categoryId!);
    }

    final city = filters.city?.trim();
    if (city != null && city.isNotEmpty) {
      query = query.eq('city', city);
    }
    if (filters.priceFrom != null) {
      query = query.gte('price', filters.priceFrom!);
    }
    if (filters.priceTo != null) {
      query = query.lte('price', filters.priceTo!);
    }
    if (filters.condition != null) {
      query = query.eq('condition', filters.condition!.dbValue);
    }
    if (filters.dateFrom != null) {
      query = query.gte(
        'created_at',
        filters.dateFrom!.toUtc().toIso8601String(),
      );
    }

    final q = filters.query.trim();
    if (q.isNotEmpty) {
      final safe = q.replaceAll(',', ' ').replaceAll('%', '');
      query = query.or('title.ilike.%$safe%,description.ilike.%$safe%');
    }

    return switch (filters.sort) {
      ListingSort.newest => query
          .order('is_promoted', ascending: false)
          .order('boosted_at', ascending: false, nullsFirst: false)
          .order('created_at', ascending: false),
      ListingSort.cheapest => query
          .order('is_promoted', ascending: false)
          .order('boosted_at', ascending: false, nullsFirst: false)
          .order('price', ascending: true),
      ListingSort.expensive => query
          .order('is_promoted', ascending: false)
          .order('boosted_at', ascending: false, nullsFirst: false)
          .order('price', ascending: false),
      ListingSort.popular => query
          .order('is_promoted', ascending: false)
          .order('boosted_at', ascending: false, nullsFirst: false)
          .order('views_count', ascending: false),
    };
  }

  List<Listing> _mapRows(dynamic rows) {
    return (rows as List)
        .map((e) => Listing.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Listing> fetchById(String id) async {
    try {
      final row = await _client
          .from('listings')
          .select(_selectLite)
          .eq('id', id)
          .single()
          .timeout(const Duration(seconds: 15));
      var listing = Listing.fromJson(Map<String, dynamic>.from(row));

      try {
        final imgs = await _client
            .from('listing_images')
            .select('id, listing_id, url, sort_order, created_at')
            .eq('listing_id', id)
            .order('sort_order', ascending: true)
            .timeout(const Duration(seconds: 10));
        final images = (imgs as List)
            .map((e) => ListingImage.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        listing = listing.copyWith(images: images);
      } catch (_) {}

      try {
        final seller = await _client
            .from('profiles')
            .select('nickname')
            .eq('id', listing.sellerId)
            .maybeSingle()
            .timeout(const Duration(seconds: 8));
        final nick = seller?['nickname'] as String?;
        if (nick != null) {
          listing = listing.copyWith(sellerNickname: nick);
        }
      } catch (_) {}

      final fav = await _isFavorite(id);
      return listing.copyWith(isFavorite: fav);
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<List<Listing>> fetchMyListings({ListingStatus? status}) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        throw const AppException('Требуется авторизация');
      }

      var query = _client
          .from('listings')
          .select(_selectLite)
          .eq('seller_id', userId);

      if (status != null) {
        query = query.eq('status', status.name);
      }

      final rows = await query
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 15));
      final list = (rows as List)
          .map((e) => Listing.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      return _attachImagesAndFavorites(list);
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<Listing> createListing({
    required String categoryId,
    required String title,
    required String description,
    required double price,
    required String city,
    required ListingCondition condition,
    ListingStatus status = ListingStatus.pending,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        throw const AppException('Требуется авторизация');
      }

      final row = await _client
          .from('listings')
          .insert({
            'seller_id': userId,
            'category_id': categoryId,
            'title': title.trim(),
            'description': description.trim(),
            'price': price,
            'city': city.trim(),
            'condition': condition.dbValue,
            'status': status.name,
          })
          .select(_selectLite)
          .single();

      return Listing.fromJson(Map<String, dynamic>.from(row));
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<Listing> updateListing({
    required String id,
    required String categoryId,
    required String title,
    required String description,
    required double price,
    required String city,
    required ListingCondition condition,
  }) async {
    try {
      final row = await _client
          .from('listings')
          .update({
            'category_id': categoryId,
            'title': title.trim(),
            'description': description.trim(),
            'price': price,
            'city': city.trim(),
            'condition': condition.dbValue,
          })
          .eq('id', id)
          .select(_selectLite)
          .single();
      final listing = Listing.fromJson(Map<String, dynamic>.from(row));
      final fav = await _isFavorite(id);
      return listing.copyWith(isFavorite: fav);
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<Listing> setStatus(String id, ListingStatus status) async {
    try {
      final row = await _client
          .from('listings')
          .update({'status': status.name})
          .eq('id', id)
          .select(_selectLite)
          .single();
      return Listing.fromJson(Map<String, dynamic>.from(row));
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<void> deleteListing(String id) async {
    try {
      await _client.from('listings').delete().eq('id', id);
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<ListingImage> addImage({
    required String listingId,
    required String url,
    required int sortOrder,
  }) async {
    try {
      final row = await _client
          .from('listing_images')
          .insert({
            'listing_id': listingId,
            'url': url,
            'sort_order': sortOrder,
          })
          .select('id, listing_id, url, sort_order, created_at')
          .single();
      return ListingImage.fromJson(Map<String, dynamic>.from(row));
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<void> deleteImage(String imageId) async {
    try {
      await _client.from('listing_images').delete().eq('id', imageId);
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<void> reorderImages(List<ListingImage> images) async {
    try {
      for (var i = 0; i < images.length; i++) {
        await _client
            .from('listing_images')
            .update({'sort_order': i})
            .eq('id', images[i].id);
      }
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<bool> toggleFavorite(String listingId) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        throw const AppException('Требуется авторизация');
      }

      final existing = await _client
          .from('listing_favorites')
          .select('listing_id')
          .eq('user_id', userId)
          .eq('listing_id', listingId)
          .maybeSingle();

      if (existing != null) {
        await _client
            .from('listing_favorites')
            .delete()
            .eq('user_id', userId)
            .eq('listing_id', listingId);
        return false;
      }

      await _client.from('listing_favorites').insert({
        'user_id': userId,
        'listing_id': listingId,
      });
      return true;
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<void> incrementViews(String listingId) async {
    try {
      await _client.rpc(
        'increment_listing_views',
        params: {'p_listing_id': listingId},
      );
    } catch (_) {
      // Non-critical.
    }
  }

  Future<List<Listing>> _attachImagesAndFavorites(List<Listing> list) async {
    if (list.isEmpty) return list;

    var withImages = list;
    try {
      final ids = list.map((e) => e.id).toList();
      final rows = await _client
          .from('listing_images')
          .select('id, listing_id, url, sort_order, created_at')
          .inFilter('listing_id', ids)
          .order('sort_order', ascending: true)
          .timeout(const Duration(seconds: 12));

      final byListing = <String, List<ListingImage>>{};
      for (final row in rows as List) {
        final img = ListingImage.fromJson(Map<String, dynamic>.from(row as Map));
        byListing.putIfAbsent(img.listingId, () => []).add(img);
      }
      withImages = [
        for (final item in list)
          item.copyWith(images: byListing[item.id] ?? const []),
      ];
    } catch (_) {
      // Feed still works without covers.
    }

    return _attachFavorites(withImages);
  }

  Future<List<Listing>> _attachFavorites(List<Listing> list) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || list.isEmpty) return list;

    try {
      final ids = list.map((e) => e.id).toList();
      final rows = await _client
          .from('listing_favorites')
          .select('listing_id')
          .eq('user_id', userId)
          .inFilter('listing_id', ids)
          .timeout(const Duration(seconds: 10));

      final favIds = {
        for (final row in rows as List) (row as Map)['listing_id'] as String,
      };

      return [
        for (final item in list)
          item.copyWith(isFavorite: favIds.contains(item.id)),
      ];
    } catch (_) {
      return list;
    }
  }

  Future<bool> _isFavorite(String listingId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    final row = await _client
        .from('listing_favorites')
        .select('listing_id')
        .eq('user_id', userId)
        .eq('listing_id', listingId)
        .maybeSingle();
    return row != null;
  }
}
