import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared responsive metrics for phones / large phones / small tablets.
///
/// Portrait-only app: widths typically 320–900 logical px.
abstract final class AppLayout {
  static const double compactWidth = 360;
  static const double phoneWidth = 600;
  static const double contentMaxWidth = 560;
  static const double formMaxWidth = 420;

  static Size sizeOf(BuildContext context) => MediaQuery.sizeOf(context);

  static double widthOf(BuildContext context) => sizeOf(context).width;

  static double heightOf(BuildContext context) => sizeOf(context).height;

  static bool isCompact(BuildContext context) => widthOf(context) < compactWidth;

  static bool isTablet(BuildContext context) => widthOf(context) >= phoneWidth;

  /// Horizontal page gutter (tighter on very small phones).
  static double pageGutter(BuildContext context) {
    final w = widthOf(context);
    if (w < compactWidth) return 12;
    if (w >= phoneWidth) return 24;
    return 16;
  }

  static EdgeInsets pagePadding(
    BuildContext context, {
    double top = 4,
    double bottom = 20,
  }) {
    final g = pageGutter(context);
    return EdgeInsets.fromLTRB(g, top, g, bottom);
  }

  /// Caps content width on wide devices; keeps full height for lists.
  static Widget constrain({
    required BuildContext context,
    required Widget child,
    double maxWidth = contentMaxWidth,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(maxWidth, constraints.maxWidth);
        final height =
            constraints.hasBoundedHeight ? constraints.maxHeight : null;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            height: height,
            child: child,
          ),
        );
      },
    );
  }

  /// Cross-axis count for badge/photo grids.
  static int gridCount(
    BuildContext context, {
    double minTile = 108,
    int minCount = 2,
    int maxCount = 4,
  }) {
    final usable = math.min(widthOf(context), contentMaxWidth) -
        pageGutter(context) * 2;
    final count = (usable / minTile).floor();
    return count.clamp(minCount, maxCount);
  }

  /// Event list thumb / card height (square thumb).
  static double eventListThumb(BuildContext context) {
    final w = widthOf(context);
    if (w < compactWidth) return 100;
    if (w >= phoneWidth) return 140;
    return 120;
  }

  /// Market listing row thumb width.
  static double listingThumbWidth(BuildContext context) {
    final w = widthOf(context);
    if (w < compactWidth) return 84;
    if (w >= phoneWidth) return 112;
    return 96;
  }

  /// Listing detail hero height (fraction of screen, capped).
  static double listingHeroHeight(BuildContext context) {
    final h = heightOf(context);
    return (h * 0.36).clamp(200.0, 360.0);
  }

  /// Chat image bubble max size.
  static double chatImageMax(BuildContext context) {
    return math.min(220.0, widthOf(context) * 0.55);
  }

  /// Voice message bubble width.
  static double chatVoiceWidth(BuildContext context) {
    return math.min(180.0, widthOf(context) * 0.48);
  }

  /// QR code display size.
  static double qrSize(BuildContext context) {
    final usable = math.min(widthOf(context), formMaxWidth) -
        pageGutter(context) * 2 -
        48;
    return usable.clamp(160.0, 240.0);
  }

  /// Stats value font size scales down on compact widths.
  static double statsValueFont(BuildContext context) {
    return isCompact(context) ? 16.0 : 20.0;
  }
}
