import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import 'map_lat_lng.dart';

export 'map_lat_lng.dart';

/// Web / desktop stub — MapKit is Android/iOS only.
class YandexMapView extends StatelessWidget {
  const YandexMapView({
    super.key,
    required this.latitude,
    required this.longitude,
    this.zoom = 15,
    this.interactivePin = false,
    this.onPinChanged,
  });

  final double latitude;
  final double longitude;
  final double zoom;
  final bool interactivePin;
  final ValueChanged<MapLatLng>? onPinChanged;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surfaceElevated,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Яндекс.Карта доступна только в приложении на Android / iOS.\n'
            '($latitude, $longitude)',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}
