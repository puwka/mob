import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import 'app_network_image.dart';

/// Fullscreen gallery viewer (swipe + pinch).
void showPhotoLightbox(
  BuildContext context, {
  required List<String> urls,
  int initialIndex = 0,
}) {
  final cleaned = [
    for (final u in urls)
      if (u.trim().isNotEmpty) u.trim(),
  ];
  if (cleaned.isEmpty) return;

  final index = initialIndex.clamp(0, cleaned.length - 1);
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Закрыть',
    barrierColor: Colors.black.withValues(alpha: 0.92),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _PhotoLightbox(
        urls: cleaned,
        initialIndex: index,
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

class _PhotoLightbox extends StatefulWidget {
  const _PhotoLightbox({
    required this.urls,
    required this.initialIndex,
  });

  final List<String> urls;
  final int initialIndex;

  @override
  State<_PhotoLightbox> createState() => _PhotoLightboxState();
}

class _PhotoLightboxState extends State<_PhotoLightbox> {
  late final PageController _pageController;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.urls.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: AppNetworkImage(
                      url: widget.urls[i],
                      fit: BoxFit.contain,
                      memCacheWidth: 1600,
                      filterQuality: FilterQuality.medium,
                      backgroundColor: Colors.transparent,
                      showSpinner: true,
                      debugLabel: 'photo-lightbox',
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                tooltip: 'Закрыть',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
            if (widget.urls.length > 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: Text(
                  '${_index + 1} / ${widget.urls.length}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
