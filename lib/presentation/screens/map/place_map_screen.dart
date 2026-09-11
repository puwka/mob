import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../services/map_launcher.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/yandex_map_view.dart';

/// Read-only in-app Yandex map with a pin.
class PlaceMapScreen extends StatelessWidget {
  const PlaceMapScreen({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.title,
    this.subtitle,
  });

  final double latitude;
  final double longitude;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final address = subtitle?.trim();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(title)),
      body: Stack(
        children: [
          YandexMapView(
            latitude: latitude,
            longitude: longitude,
            zoom: 15,
          ),
          if (address != null && address.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: SafeArea(
                child: Material(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.place_outlined,
                              color: AppColors.accent,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                address,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  height: 1.35,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        AppButton(
                          label: 'Открыть в Яндекс Картах',
                          onPressed: () async {
                            try {
                              await MapLauncher.open(
                                latitude: latitude,
                                longitude: longitude,
                                query: address,
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(ErrorMapper.map(e))),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Opens [PlaceMapScreen]. Geocodes [query] when coordinates are missing.
Future<void> openPlaceMapInApp(
  BuildContext context, {
  double? latitude,
  double? longitude,
  String? query,
  String title = 'На карте',
}) async {
  final q = (query ?? '').trim();
  var lat = latitude;
  var lng = longitude;

  if (lat == null || lng == null) {
    if (q.isEmpty) {
      throw const AppException('Адрес не указан');
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
    try {
      final hit = await GeocodingService.searchFirst(q);
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (hit == null) {
        throw const AppException('Не удалось найти точку на карте');
      }
      lat = hit.lat;
      lng = hit.lng;
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      rethrow;
    }
  }

  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => PlaceMapScreen(
        latitude: lat!,
        longitude: lng!,
        title: title,
        subtitle: q.isEmpty ? null : q,
      ),
    ),
  );
}
