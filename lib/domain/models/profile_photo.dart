class ProfilePhoto {
  const ProfilePhoto({
    required this.id,
    required this.userId,
    required this.url,
    required this.sortOrder,
  });

  final String id;
  final String userId;
  final String url;
  final int sortOrder;

  factory ProfilePhoto.fromJson(Map<String, dynamic> json) {
    return ProfilePhoto(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      url: json['url'] as String,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}
