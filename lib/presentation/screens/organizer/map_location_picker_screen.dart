import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/models/polygon.dart';
import '../../../services/map_launcher.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_text_field.dart';

/// Full-screen OSM map to pick a pin. Returns [MapPickResult] via Navigator.
class MapLocationPickerScreen extends StatefulWidget {
  const MapLocationPickerScreen({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialAddress,
    this.title = 'Точка на карте',
  });

  final double? initialLatitude;
  final double? initialLongitude;
  final String? initialAddress;
  final String title;

  @override
  State<MapLocationPickerScreen> createState() =>
      _MapLocationPickerScreenState();
}

class _MapLocationPickerScreenState extends State<MapLocationPickerScreen> {
  static const _default = LatLng(55.7558, 37.6173);

  late final MapController _mapController;
  late LatLng _pin;
  late final TextEditingController _search;
  late final TextEditingController _address;
  var _resolving = false;
  var _searching = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _pin = LatLng(
      widget.initialLatitude ?? _default.latitude,
      widget.initialLongitude ?? _default.longitude,
    );
    _search = TextEditingController();
    _address = TextEditingController(text: widget.initialAddress ?? '');
    if ((widget.initialAddress == null || widget.initialAddress!.isEmpty) &&
        widget.initialLatitude != null) {
      _reverse();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _address.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _reverse() async {
    setState(() => _resolving = true);
    final addr = await GeocodingService.reverseAddress(
      latitude: _pin.latitude,
      longitude: _pin.longitude,
    );
    if (!mounted) return;
    setState(() {
      _resolving = false;
      if (addr != null && addr.isNotEmpty) {
        _address.text = addr;
      }
    });
  }

  Future<void> _runSearch() async {
    FocusScope.of(context).unfocus();
    setState(() => _searching = true);
    final hit = await GeocodingService.searchFirst(_search.text);
    if (!mounted) return;
    setState(() => _searching = false);
    if (hit == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Адрес не найден')),
      );
      return;
    }
    setState(() {
      _pin = LatLng(hit.lat, hit.lng);
      _address.text = hit.label;
    });
    _mapController.move(_pin, 15);
  }

  void _confirm() {
    final address = _address.text.trim();
    Navigator.of(context).pop(
      MapPickResult(
        latitude: _pin.latitude,
        longitude: _pin.longitude,
        address: address.isEmpty ? null : address,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _search,
                    label: 'Поиск адреса',
                    prefixIcon: Icons.search,
                    textInputAction: TextInputAction.search,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 96,
                  child: AppButton(
                    label: _searching ? '…' : 'Найти',
                    expand: true,
                    onPressed: _searching ? null : _runSearch,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _pin,
                    initialZoom: 13,
                    onTap: (_, point) {
                      setState(() => _pin = point);
                      _reverse();
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.moystraykbol.app',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _pin,
                          width: 48,
                          height: 48,
                          child: const Icon(
                            Icons.location_on,
                            color: AppColors.accent,
                            size: 44,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Material(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _resolving
                                ? 'Определяем адрес…'
                                : 'Нажмите на карту, чтобы поставить метку',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          AppTextField(
                            controller: _address,
                            label: 'Адрес',
                            maxLines: 2,
                          ),
                          const SizedBox(height: 10),
                          AppButton(
                            label: 'Сохранить точку',
                            onPressed: _confirm,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<MapPickResult?> openMapLocationPicker(
  BuildContext context, {
  double? latitude,
  double? longitude,
  String? address,
  String title = 'Точка на карте',
}) {
  return Navigator.of(context).push<MapPickResult>(
    MaterialPageRoute(
      builder: (_) => MapLocationPickerScreen(
        initialLatitude: latitude,
        initialLongitude: longitude,
        initialAddress: address,
        title: title,
      ),
    ),
  );
}
