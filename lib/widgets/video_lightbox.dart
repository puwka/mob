import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../core/theme/app_colors.dart';

/// Fullscreen chat video viewer (Telegram-style).
void showVideoLightbox(
  BuildContext context, {
  required String url,
  int? durationMs,
}) {
  final cleaned = url.trim();
  if (cleaned.isEmpty) return;

  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Закрыть',
    barrierColor: Colors.black.withValues(alpha: 0.96),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _VideoLightbox(
        url: cleaned,
        durationMs: durationMs,
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

class _VideoLightbox extends StatefulWidget {
  const _VideoLightbox({
    required this.url,
    this.durationMs,
  });

  final String url;
  final int? durationMs;

  @override
  State<_VideoLightbox> createState() => _VideoLightboxState();
}

class _VideoLightboxState extends State<_VideoLightbox> {
  VideoPlayerController? _controller;
  var _loading = true;
  var _failed = false;
  var _showChrome = true;
  var _playing = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _init();
  }

  Future<void> _init() async {
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await controller.initialize();
      controller.addListener(_onTick);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
      await controller.play();
      _scheduleHideChrome();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _onTick() {
    final c = _controller;
    if (c == null || !mounted) return;
    final playing = c.value.isPlaying;
    if (playing != _playing) {
      setState(() => _playing = playing);
      if (playing) {
        _scheduleHideChrome();
      } else {
        _hideTimer?.cancel();
        if (!_showChrome) setState(() => _showChrome = true);
      }
      return;
    }
    // Update scrubber only while chrome is visible.
    if (_showChrome) setState(() {});
  }

  void _scheduleHideChrome() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (_controller?.value.isPlaying == true) {
        setState(() => _showChrome = false);
      }
    });
  }

  void _toggleChrome() {
    setState(() => _showChrome = !_showChrome);
    if (_showChrome && _playing) _scheduleHideChrome();
  }

  Future<void> _togglePlay() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      if (c.value.position >= c.value.duration &&
          c.value.duration > Duration.zero) {
        await c.seekTo(Duration.zero);
      }
      await c.play();
      _scheduleHideChrome();
    }
  }

  String _fmt(Duration d) {
    final total = d.inSeconds.clamp(0, 99999);
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    final duration = ready
        ? c.value.duration
        : Duration(milliseconds: widget.durationMs ?? 0);
    final position = ready ? c.value.position : Duration.zero;
    final maxMs = duration.inMilliseconds <= 0
        ? 1.0
        : duration.inMilliseconds.toDouble();

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: ready ? _toggleChrome : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: _loading
                  ? const SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : _failed || !ready
                      ? const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.videocam_off_outlined,
                              color: Colors.white70,
                              size: 48,
                            ),
                            SizedBox(height: 10),
                            Text(
                              'Не удалось воспроизвести видео',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        )
                      : AspectRatio(
                          aspectRatio: c.value.aspectRatio == 0
                              ? 16 / 9
                              : c.value.aspectRatio,
                          child: VideoPlayer(c),
                        ),
            ),
            if (ready && _showChrome)
              Center(
                child: GestureDetector(
                  onTap: _togglePlay,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: Color(0x99000000),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
              ),
            AnimatedOpacity(
              opacity: _showChrome || !ready ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: SafeArea(
                child: Stack(
                  children: [
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IconButton(
                        tooltip: 'Закрыть',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ),
                    if (ready)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 16,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2.5,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 7,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 14,
                                ),
                                activeTrackColor: AppColors.accent,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.white,
                                overlayColor: AppColors.accent.withValues(
                                  alpha: 0.25,
                                ),
                              ),
                              child: Slider(
                                value: position.inMilliseconds
                                    .clamp(0, maxMs.toInt())
                                    .toDouble(),
                                max: maxMs,
                                onChanged: (v) {
                                  c.seekTo(Duration(milliseconds: v.round()));
                                  _scheduleHideChrome();
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(
                                children: [
                                  Text(
                                    _fmt(position),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _fmt(duration),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
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
