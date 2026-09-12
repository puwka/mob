import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/models/dating.dart';
import '../../../services/app_image_cache.dart';
import '../../../widgets/app_network_image.dart';

/// Horizontal swipe / tap photo pager with page dots.
class DatingPhotoViewer extends StatefulWidget {
  const DatingPhotoViewer({
    super.key,
    required this.photos,
    this.onIndexChanged,
  });

  final List<String> photos;
  final ValueChanged<int>? onIndexChanged;

  @override
  State<DatingPhotoViewer> createState() => _DatingPhotoViewerState();
}

class _DatingPhotoViewerState extends State<DatingPhotoViewer> {
  late final PageController _controller;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _prefetchAround(0);
  }

  @override
  void didUpdateWidget(covariant DatingPhotoViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photos != widget.photos) {
      _index = 0;
      if (_controller.hasClients) {
        _controller.jumpToPage(0);
      }
      _prefetchAround(0);
    }
  }

  void _prefetchAround(int index) {
    final photos = widget.photos;
    if (photos.isEmpty) return;
    final urls = <String?>[
      if (index < photos.length) photos[index],
      if (index + 1 < photos.length) photos[index + 1],
      if (index + 2 < photos.length) photos[index + 2],
    ];
    AppImageCache.prefetch(urls, limit: 3);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    final photos = widget.photos;
    if (photos.length <= 1) return;
    final next = index.clamp(0, photos.length - 1);
    if (next == _index) return;
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _onTapSide(TapUpDetails details, BoxConstraints constraints) {
    if (widget.photos.length <= 1) return;
    final dx = details.localPosition.dx;
    if (dx < constraints.maxWidth * 0.35) {
      _goTo(_index - 1);
    } else if (dx > constraints.maxWidth * 0.65) {
      _goTo(_index + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    if (photos.isEmpty) {
      return const ColoredBox(
        color: AppColors.surfaceElevated,
        child: Center(
          child: Icon(
            Icons.person_outline,
            size: 64,
            color: AppColors.textTertiary,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: photos.length > 1
              ? (d) => _onTapSide(d, constraints)
              : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: photos.length,
                physics: photos.length > 1
                    ? const PageScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                onPageChanged: (i) {
                  setState(() => _index = i);
                  widget.onIndexChanged?.call(i);
                  _prefetchAround(i);
                },
                itemBuilder: (context, i) {
                  final w = constraints.maxWidth;
                  final h = constraints.maxHeight;
                  return AppNetworkImage(
                    url: photos[i],
                    fit: BoxFit.cover,
                    width: w.isFinite ? w : null,
                    height: h.isFinite ? h : null,
                    memCacheWidth: (w.isFinite ? w : 420).round().clamp(320, 900),
                    memCacheHeight:
                        (h.isFinite ? h : 640).round().clamp(480, 1200),
                    filterQuality: FilterQuality.medium,
                    showSpinner: true,
                    debugLabel: 'dating',
                    placeholderIcon: Icons.person_outline,
                  );
                },
              ),
              if (photos.length > 1)
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: IgnorePointer(
                    child: Row(
                      children: List.generate(photos.length, (i) {
                        final active = i == _index;
                        return Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: EdgeInsets.only(
                              right: i == photos.length - 1 ? 0 : 4,
                            ),
                            height: 3,
                            decoration: BoxDecoration(
                              color: active
                                  ? AppColors.accent
                                  : Colors.white.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              if (photos.length > 1)
                Positioned(
                  bottom: 72,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(photos.length, (i) {
                        final active = i == _index;
                        return Container(
                          width: active ? 7 : 6,
                          height: active ? 7 : 6,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: active
                                ? AppColors.accent
                                : Colors.white.withValues(alpha: 0.4),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.25),
                              width: 0.5,
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class DatingProfileCard extends StatelessWidget {
  const DatingProfileCard({
    super.key,
    required this.candidate,
    this.onOpenProfile,
  });

  final DatingCandidate candidate;
  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final photos = candidate.displayPhotos;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.card - 0.5),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DatingPhotoViewer(photos: photos),
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x330A0B0D),
                      Color(0x000A0B0D),
                      Color(0xCC0A0B0D),
                    ],
                    stops: [0, 0.45, 1],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: GestureDetector(
                onTap: onOpenProfile,
                behavior: HitTestBehavior.opaque,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      candidate.age != null
                          ? '${candidate.nickname}, ${candidate.age}'
                          : candidate.nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 15,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            candidate.city,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DatingActionButtons extends StatelessWidget {
  const DatingActionButtons({
    super.key,
    required this.onSkip,
    required this.onLike,
    this.enabled = true,
    this.busy = false,
  });

  final VoidCallback? onSkip;
  final VoidCallback? onLike;
  final bool enabled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final canTap = enabled && !busy;

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 52,
            child: OutlinedButton(
              onPressed: canTap ? onSkip : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.button),
                ),
              ),
              child: const Text(
                'Пропустить',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 1,
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: canTap ? onLike : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: const Color(0xFF12140A),
                disabledBackgroundColor: AppColors.accentSoft,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.button),
                ),
                elevation: 0,
              ),
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF12140A),
                      ),
                    )
                  : const Text(
                      'Дружить',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class DatingCardSkeleton extends StatelessWidget {
  const DatingCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.card - 0.5),
        child: const ColoredBox(
          color: AppColors.surfaceElevated,
          child: Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ),
    );
  }
}
