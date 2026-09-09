import 'dart:developer' as developer;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Shared network image with disk cache, placeholders, and debug logging.
class AppNetworkImage extends StatelessWidget {
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

  void _logError(Object error, String resolved) {
    developer.log(
      'IMAGE_FAIL label=${debugLabel ?? '-'} url=$resolved error=$error',
      name: 'STORAGE',
      level: 900,
    );
    if (kDebugMode) {
      debugPrint('[STORAGE] IMAGE_FAIL ${debugLabel ?? ''} $resolved → $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final raw = url?.trim();
    if (raw == null || raw.isEmpty) {
      return _Placeholder(
        width: width,
        height: height,
        color: backgroundColor,
        icon: placeholderIcon,
        iconSize: iconSize,
        borderRadius: borderRadius,
      );
    }

    final cacheW = memCacheWidth ??
        (width != null && width!.isFinite ? (width! * 2).round() : 720);
    final cacheH = memCacheHeight ??
        (height != null && height!.isFinite ? (height! * 2).round() : null);

    Widget image = CachedNetworkImage(
      imageUrl: raw,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: cacheW,
      memCacheHeight: cacheH,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (context, _) => _Placeholder(
        width: width,
        height: height,
        color: backgroundColor,
        icon: placeholderIcon,
        iconSize: iconSize,
        showSpinner: true,
      ),
      errorWidget: (context, failedUrl, error) {
        _logError(error, failedUrl);
        return _Placeholder(
          width: width,
          height: height,
          color: backgroundColor,
          icon: errorIcon,
          iconSize: iconSize,
        );
      },
    );

    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius!, child: image);
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
    }
    if (borderRadius != null) {
      child = ClipRRect(borderRadius: borderRadius!, child: child);
    }
    return child;
  }
}
