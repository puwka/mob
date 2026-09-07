class MarketCategory {
  const MarketCategory({
    required this.id,
    required this.name,
    this.parentId,
    this.icon,
    required this.sortOrder,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String? parentId;
  final String? icon;
  final int sortOrder;
  final DateTime createdAt;

  bool get isRoot => parentId == null;

  factory MarketCategory.fromJson(Map<String, dynamic> json) {
    return MarketCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      parentId: json['parent_id'] as String?,
      icon: json['icon'] as String?,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

enum ListingStatus {
  pending,
  active,
  sold,
  archived,
  rejected;

  static ListingStatus fromString(String value) {
    return ListingStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ListingStatus.active,
    );
  }

  String get labelRu => switch (this) {
        ListingStatus.pending => 'На модерации',
        ListingStatus.active => 'Активные',
        ListingStatus.sold => 'Проданные',
        ListingStatus.archived => 'Архив',
        ListingStatus.rejected => 'Отклонённые',
      };
}

enum ListingCondition {
  brandNew,
  likeNew,
  used;

  static ListingCondition fromString(String value) {
    return switch (value) {
      'new' => ListingCondition.brandNew,
      'like_new' => ListingCondition.likeNew,
      _ => ListingCondition.used,
    };
  }

  String get dbValue => switch (this) {
        ListingCondition.brandNew => 'new',
        ListingCondition.likeNew => 'like_new',
        ListingCondition.used => 'used',
      };

  String get labelRu => switch (this) {
        ListingCondition.brandNew => 'Новое',
        ListingCondition.likeNew => 'Как новое',
        ListingCondition.used => 'Б/у',
      };
}

enum ListingSort {
  newest,
  cheapest,
  expensive,
  popular;

  String get labelRu => switch (this) {
        ListingSort.newest => 'Новые',
        ListingSort.cheapest => 'Дешевле',
        ListingSort.expensive => 'Дороже',
        ListingSort.popular => 'Популярные',
      };
}

class ListingImage {
  const ListingImage({
    required this.id,
    required this.listingId,
    required this.url,
    required this.sortOrder,
    required this.createdAt,
  });

  final String id;
  final String listingId;
  final String url;
  final int sortOrder;
  final DateTime createdAt;

  factory ListingImage.fromJson(Map<String, dynamic> json) {
    return ListingImage(
      id: json['id'] as String,
      listingId: json['listing_id'] as String,
      url: json['url'] as String,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class Listing {
  const Listing({
    required this.id,
    required this.sellerId,
    required this.categoryId,
    required this.title,
    required this.description,
    required this.price,
    required this.city,
    required this.condition,
    required this.status,
    required this.viewsCount,
    required this.isPromoted,
    this.promotedUntil,
    required this.createdAt,
    required this.updatedAt,
    this.sellerNickname,
    this.categoryName,
    this.parentCategoryName,
    this.images = const [],
    this.isFavorite = false,
  });

  final String id;
  final String sellerId;
  final String categoryId;
  final String title;
  final String description;
  final double price;
  final String city;
  final ListingCondition condition;
  final ListingStatus status;
  final int viewsCount;
  final bool isPromoted;
  final DateTime? promotedUntil;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? sellerNickname;
  final String? categoryName;
  final String? parentCategoryName;
  final List<ListingImage> images;
  final bool isFavorite;

  String? get coverUrl =>
      images.isEmpty ? null : images.first.url;

  String get priceLabel {
    final v = price == price.roundToDouble()
        ? price.toInt().toString()
        : price.toStringAsFixed(0);
    return '$v ₽';
  }

  String get shortSpecs {
    final cat = (parentCategoryName != null && parentCategoryName!.isNotEmpty)
        ? parentCategoryName!
        : (categoryName ?? '');
    final parts = <String>[
      if (cat.isNotEmpty) cat,
      condition.labelRu,
    ];
    return parts.join(' · ');
  }

  bool get isPromotionActive {
    if (!isPromoted) return false;
    if (promotedUntil == null) return true;
    return promotedUntil!.isAfter(DateTime.now());
  }

  Listing copyWith({
    List<ListingImage>? images,
    bool? isFavorite,
    ListingStatus? status,
    int? viewsCount,
    String? sellerNickname,
    String? categoryName,
    String? parentCategoryName,
  }) {
    return Listing(
      id: id,
      sellerId: sellerId,
      categoryId: categoryId,
      title: title,
      description: description,
      price: price,
      city: city,
      condition: condition,
      status: status ?? this.status,
      viewsCount: viewsCount ?? this.viewsCount,
      isPromoted: isPromoted,
      promotedUntil: promotedUntil,
      createdAt: createdAt,
      updatedAt: updatedAt,
      sellerNickname: sellerNickname ?? this.sellerNickname,
      categoryName: categoryName ?? this.categoryName,
      parentCategoryName: parentCategoryName ?? this.parentCategoryName,
      images: images ?? this.images,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  factory Listing.fromJson(
    Map<String, dynamic> json, {
    bool? isFavorite,
  }) {
    String? sellerNick;
    final seller = json['seller'];
    if (seller is Map) {
      sellerNick = seller['nickname'] as String?;
    } else if (seller is List && seller.isNotEmpty) {
      final first = seller.first;
      if (first is Map) sellerNick = first['nickname'] as String?;
    }

    String? catName;
    String? parentName;
    final category = json['category'];
    if (category is Map) {
      catName = category['name'] as String?;
      // Parent name resolved later via categories cache if needed.
      parentName = category['parent_name'] as String?;
      final parent = category['parent'];
      if (parent is Map) {
        parentName = parent['name'] as String?;
      }
    }

    final imagesRaw = json['listing_images'];
    final images = <ListingImage>[];
    if (imagesRaw is List) {
      for (final row in imagesRaw) {
        if (row is Map) {
          images.add(ListingImage.fromJson(Map<String, dynamic>.from(row)));
        }
      }
      images.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }

    return Listing(
      id: json['id'] as String,
      sellerId: json['seller_id'] as String,
      categoryId: json['category_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      price: (json['price'] as num).toDouble(),
      city: json['city'] as String,
      condition: ListingCondition.fromString(
        json['condition'] as String? ?? 'used',
      ),
      status: ListingStatus.fromString(json['status'] as String? ?? 'active'),
      viewsCount: (json['views_count'] as num?)?.toInt() ?? 0,
      isPromoted: json['is_promoted'] as bool? ?? false,
      promotedUntil: json['promoted_until'] == null
          ? null
          : DateTime.parse(json['promoted_until'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      sellerNickname: sellerNick,
      categoryName: catName,
      parentCategoryName: parentName,
      images: images,
      isFavorite: isFavorite ?? false,
    );
  }
}

class ListingFilters {
  const ListingFilters({
    this.query = '',
    this.city,
    this.categoryId,
    this.subcategoryId,
    this.priceFrom,
    this.priceTo,
    this.condition,
    this.dateFrom,
    this.sort = ListingSort.newest,
  });

  final String query;
  final String? city;
  final String? categoryId;
  final String? subcategoryId;
  final double? priceFrom;
  final double? priceTo;
  final ListingCondition? condition;
  final DateTime? dateFrom;
  final ListingSort sort;

  ListingFilters copyWith({
    String? query,
    String? city,
    bool clearCity = false,
    String? categoryId,
    bool clearCategory = false,
    String? subcategoryId,
    bool clearSubcategory = false,
    double? priceFrom,
    bool clearPriceFrom = false,
    double? priceTo,
    bool clearPriceTo = false,
    ListingCondition? condition,
    bool clearCondition = false,
    DateTime? dateFrom,
    bool clearDateFrom = false,
    ListingSort? sort,
  }) {
    return ListingFilters(
      query: query ?? this.query,
      city: clearCity ? null : (city ?? this.city),
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      subcategoryId:
          clearSubcategory ? null : (subcategoryId ?? this.subcategoryId),
      priceFrom: clearPriceFrom ? null : (priceFrom ?? this.priceFrom),
      priceTo: clearPriceTo ? null : (priceTo ?? this.priceTo),
      condition: clearCondition ? null : (condition ?? this.condition),
      dateFrom: clearDateFrom ? null : (dateFrom ?? this.dateFrom),
      sort: sort ?? this.sort,
    );
  }

  bool get hasActiveFilters =>
      (city != null && city!.isNotEmpty) ||
      categoryId != null ||
      subcategoryId != null ||
      priceFrom != null ||
      priceTo != null ||
      condition != null ||
      dateFrom != null ||
      query.trim().isNotEmpty;
}
