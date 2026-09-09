class PolygonVenue {
  const PolygonVenue({
    required this.id,
    required this.organizerId,
    required this.name,
    required this.city,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String organizerId;
  final String name;
  final String city;
  final String address;
  final double latitude;
  final double longitude;
  final DateTime createdAt;
  final DateTime? updatedAt;

  String get mapLabel => '$name · $address';

  factory PolygonVenue.fromJson(Map<String, dynamic> json) {
    return PolygonVenue(
      id: json['id'] as String,
      organizerId: json['organizer_id'] as String,
      name: json['name'] as String? ?? '',
      city: json['city'] as String? ?? '',
      address: json['address'] as String? ?? '',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String),
    );
  }
}

class MapPickResult {
  const MapPickResult({
    required this.latitude,
    required this.longitude,
    this.address,
  });

  final double latitude;
  final double longitude;
  final String? address;
}
