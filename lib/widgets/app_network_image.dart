import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../services/app_image_cache.dart';

/// Fast network image: disk cache, decode resize, no fade delay.
/// On decode/cache failure with memCache*, retries once at full resolution.
class AppNetworkImage extends StatefulWidget {
  const AppNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.memCacheWidth,
    this.memCacheHeight,
    this.borderRadius,
    this.placeholderIcon = Icons.image_outlined,
    this.errorIcon = Icons.broken_image_outlined,
    this.backgroundColor = AppColors.surfaceElevated,
    this.iconSize = 22,
    this.debugLabel,
    this.showSpinner = true,
    this.filterQuality = FilterQuality.low,
  });

  final String? url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final BorderRadius? borderRadius;
  final IconData placeholderIcon;
  final IconData errorIcon;
  final Color backgroundColor;
  final double iconSize;
  final String? debugLabel;
  final bool showSpinner;
  final FilterQuality filterQuality;

  @override
  State<AppNetworkImage> createState() => _AppNetworkImageState();
}

class _AppNetworkImageState extends State<AppNetworkImage> {
  var _generation = 0;
  var _disableMemCache = false;

  void _logError(Object error, String resolved) {
    developer.log(
      'IMAGE_FAIL label=${widget.debugLabel ?? '-'} url=$resolved error=$error',
      name: 'STORAGE',
      level: 900,
    );
    if (kDebugMode) {
      debugPrint(
        '[STORAGE] IMAGE_FAIL ${widget.debugLabel ?? ''} $resolved → $error',
      );
    }
  }

  /// CachedNetworkImage breaks on non-finite width/height (e.g. infinity).
  double? _finite(double? v) =>
      (v != null && v.isFinite && v > 0) ? v : null;

  int? _resolveCachePx(BuildContext context, double? logical, int? explicit) {
    if (_disableMemCache) return null;
    if (explicit != null && explicit > 0) return explicit;
    final size = _finite(logical);
    if (size == null) return null;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return math.max(32, (size * dpr).round());
  }

  /// Passing BOTH memCacheWidth and memCacheHeight makes the engine decode at
  /// exact pixels and can stretch the bitmap before [BoxFit] runs.
  (int? width, int? height) _cacheDecodeSize({
    required int? cacheW,
    required int? cacheH,
  }) {
    if (_disableMemCache) return (null, null);
    if (cacheW != null && cacheH != null) {
      return cacheW >= cacheH ? (cacheW, null) : (null, cacheH);
    }
    return (cacheW, cacheH);
  }

  void _retry({required bool dropMemCache}) {
    if (!mounted) return;
    setState(() {
      if (dropMemCache) _disableMemCache = true;
      _generation++;
    });
  }

  @override
  void didUpdateWidget(covariant AppNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _generation = 0;
      _disableMemCache = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final raw = widget.url?.trim();
    if (raw == null || raw.isEmpty) {
      return _Placeholder(
        width: _finite(widget.width),
        height: _finite(widget.height),
        color: widget.backgroundColor,
        icon: widget.placeholderIcon,
        iconSize: widget.iconSize,
        borderRadius: widget.borderRadius,
      );
    }

    final w = _finite(widget.width);
    final h = _finite(widget.height);
    final rawCacheW = _resolveCachePx(context, w, widget.memCacheWidth);
    final rawCacheH = _resolveCachePx(context, h, widget.memCacheHeight);
    final (cacheW, cacheH) = _cacheDecodeSize(
      cacheW: rawCacheW,
      cacheH: rawCacheH,
    );

    Widget image = CachedNetworkImage(
      key: ValueKey('img-$_generation-$_disableMemCache-$raw'),
      imageUrl: raw,
      cacheManager: AppImageCache.manager,
      width: w,
      height: h,
      fit: widget.fit,
      filterQuality: widget.filterQuality,
      memCacheWidth: cacheW,
      memCacheHeight: cacheH,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      useOldImageOnUrlChange: true,
      placeholder: (context, _) => _Placeholder(
        width: w,
        height: h,
        color: widget.backgroundColor,
        icon: widget.placeholderIcon,
        iconSize: widget.iconSize,
        showSpinner: widget.showSpinner,
      ),
      errorWidget: (context, failedUrl, error) {
        _logError(error, failedUrl);
        final hadMemCache = !_disableMemCache &&
            (widget.memCacheWidth != null ||
                widget.memCacheHeight != null ||
                w != null ||
                h != null);
        if (hadMemCache) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _retry(dropMemCache: true);
          });
          return _Placeholder(
            width: w,
            height: h,
            color: widget.backgroundColor,
            icon: widget.placeholderIcon,
            iconSize: widget.iconSize,
            showSpinner: true,
          );
        }
        return GestureDetector(
          onTap: () => _retry(dropMemCache: false),
          child: _Placeholder(
            width: w,
            height: h,
            color: widget.backgroundColor,
            icon: widget.errorIcon,
            iconSize: widget.iconSize,
          ),
        );
      },
    );

    if (widget.borderRadius != null) {
      image = ClipRRect(borderRadius: widget.borderRadius!, child: image);
    }
    if (w == null && h == null) {
      image = SizedBox.expand(child: image);
    }
    return image;
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    this.width,
    this.height,
    required this.color,
    required this.icon,
    required this.iconSize,
    this.borderRadius,
    this.showSpinner = false,
  });

  final double? width;
  final double? height;
  final Color color;
  final IconData icon;
  final double iconSize;
  final BorderRadius? borderRadius;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    Widget child = ColoredBox(
      color: color,
      child: Center(
        child: showSpinner
            ? SizedBox(
                width: iconSize,
                height: iconSize,
                child: const CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, color: AppColors.textTertiary, size: iconSize),
      ),
    );
    if (width != null || height != null) {
      child = SizedBox(width: width, height: height, child: child);
    } else {
      child = SizedBox.expand(child: child);
    }
    if (borderRadius != null) {
      child = ClipRRect(borderRadius: borderRadius!, child: child);
    }
    return child;
  }
}
