/// Platform-agnostic map coordinate (avoids importing MapKit Point on web).
class MapLatLng {
  const MapLatLng({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}
