import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:yandex_maps_mapkit_lite/image.dart' as yandex_image;
import 'package:yandex_maps_mapkit_lite/mapkit.dart'
    hide Icon, TextStyle, Animation;
import 'package:yandex_maps_mapkit_lite/mapkit.dart' as ymap
    show Animation, AnimationType;
import 'package:yandex_maps_mapkit_lite/mapkit_factory.dart';
import 'package:yandex_maps_mapkit_lite/yandex_map.dart';

import '../core/theme/app_colors.dart';
import '../services/mapkit_bootstrap.dart';
import 'map_lat_lng.dart';

export 'map_lat_lng.dart';

/// Shared Yandex MapKit host with lifecycle + optional placemark / tap-to-move.
class YandexMapView extends StatefulWidget {
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
  State<YandexMapView> createState() => _YandexMapViewState();
}

class _YandexMapViewState extends State<YandexMapView>
    with WidgetsBindingObserver {
  MapWindow? _mapWindow;
  PlacemarkMapObject? _placemark;
  late Point _pin;
  yandex_image.ImageProvider? _pinIcon;
  late final _MapTapListener _tapListener;

  bool get _ready => mapkitInitialized;

  @override
  void initState() {
    super.initState();
    _pin = Point(latitude: widget.latitude, longitude: widget.longitude);
    _tapListener = _MapTapListener(_onMapTap);
    if (!_ready) return;
    WidgetsBinding.instance.addObserver(this);
    mapkit.onStart();
    unawaited(_preparePinIcon());
  }

  Future<void> _preparePinIcon() async {
    final bytes = await _drawPinPng();
    if (!mounted) return;
    _pinIcon = yandex_image.ImageProvider.fromImageProvider(
      MemoryImage(bytes),
      id: 'app-map-pin',
    );
    _syncPlacemark();
  }

  void _onMapTap(Point point) {
    if (!widget.interactivePin) return;
    setState(() => _pin = point);
    _syncPlacemark(moveCamera: false);
    widget.onPinChanged?.call(
      MapLatLng(latitude: point.latitude, longitude: point.longitude),
    );
  }

  void _syncPlacemark({bool moveCamera = true}) {
    final mapWindow = _mapWindow;
    final icon = _pinIcon;
    if (mapWindow == null) return;

    final map = mapWindow.map;
    if (moveCamera) {
      map.move(
        CameraPosition(
          _pin,
          zoom: widget.zoom,
          azimuth: 0,
          tilt: 0,
        ),
        animation: const ymap.Animation(
          type: ymap.AnimationType.Linear,
          duration: 0,
        ),
      );
    }

    if (_placemark == null) {
      final placemark = map.mapObjects.addPlacemark()..geometry = _pin;
      if (icon != null) {
        placemark.setIcon(icon);
      }
      _placemark = placemark;
    } else {
      _placemark!.geometry = _pin;
      if (icon != null) {
        _placemark!.setIcon(icon);
      }
    }
  }

  void _onMapCreated(MapWindow mapWindow) {
    _mapWindow = mapWindow;
    // Ensure session is active when the platform view appears.
    mapkit.onStart();
    final map = mapWindow.map;
    if (widget.interactivePin) {
      map.addInputListener(_tapListener);
    }
    // Immediate camera placement (no animation) — blank grid often = wrong
    // key, but delayed Smooth move can also look empty for a moment.
    _syncPlacemark();
  }

  @override
  void didUpdateWidget(covariant YandexMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_ready) return;
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude) {
      _pin = Point(latitude: widget.latitude, longitude: widget.longitude);
      _syncPlacemark();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_ready) return;
    if (state == AppLifecycleState.resumed) {
      mapkit.onStart();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      mapkit.onStop();
    }
  }

  @override
  void dispose() {
    if (_ready) {
      final map = _mapWindow?.map;
      if (map != null && widget.interactivePin) {
        map.removeInputListener(_tapListener);
      }
      // Do not call mapkit.onStop() here — Flutter may dispose/recreate the
      // platform view during navigation; stopping the global session blanks
      // tiles until the next cold start. App pause still stops via observer.
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      final hasKey =
          (dotenv.env['YANDEX_MAPKIT_API_KEY']?.trim() ?? '').isNotEmpty;
      return ColoredBox(
        color: AppColors.surfaceElevated,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              hasKey
                  ? 'Карта не инициализирована. Перезапустите приложение.'
                  : 'Не задан YANDEX_MAPKIT_API_KEY в .env.\n'
                      'Нужен ключ «MapKit — мобильный SDK» '
                      '(не JavaScript API), затем пересоберите APK.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        YandexMap(
          onMapCreated: _onMapCreated,
          platformViewType: PlatformViewType.Hybrid,
        ),
        if (kDebugMode)
          Positioned(
            left: 8,
            bottom: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0x99000000),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'MapKit ${mapkitKeyFingerprint(dotenv.env['YANDEX_MAPKIT_API_KEY'] ?? '')}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MapTapListener implements MapInputListener {
  _MapTapListener(this.onTap);

  final void Function(Point point) onTap;

  @override
  void onMapTap(Map map, Point point) => onTap(point);

  @override
  void onMapLongTap(Map map, Point point) => onTap(point);
}

Future<Uint8List> _drawPinPng() async {
  const size = 96.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final painter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(Icons.location_on.codePoint),
      style: TextStyle(
        fontSize: 78,
        color: AppColors.accent,
        fontFamily: Icons.location_on.fontFamily,
        package: Icons.location_on.fontPackage,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(
    canvas,
    Offset((size - painter.width) / 2, (size - painter.height) / 2),
  );
  final image =
      await recorder.endRecording().toImage(size.toInt(), size.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}
