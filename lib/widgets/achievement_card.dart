import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../domain/models/user_achievement_progress.dart';
import '../services/achievement_service.dart';

/// Hexagonal tactical badge matching reference achievement style.
class AchievementCard extends StatelessWidget {
  const AchievementCard({
    super.key,
    required this.item,
    required this.state,
    this.compact = false,
  });

  final UserAchievementProgress item;
  final AchievementVisualState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final unlocked = state == AchievementVisualState.unlocked;
    final inProgress = state == AchievementVisualState.progress;

    final badgeColor = unlocked
        ? AppColors.gold
        : inProgress
            ? AppColors.silver
            : AppColors.border;

    final fill = unlocked
        ? const Color(0xFF2A2410)
        : inProgress
            ? const Color(0xFF1E2228)
            : const Color(0xFF14171C);

    return Opacity(
      opacity: state == AchievementVisualState.locked ? 0.55 : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: compact ? 52 : 58,
            height: compact ? 58 : 64,
            child: CustomPaint(
              painter: _HexBadgePainter(
                fill: fill,
                stroke: badgeColor,
                strokeWidth: unlocked ? 1.6 : 1.1,
              ),
              child: Center(
                child: Icon(
                  _iconFor(item.achievement.icon),
                  size: compact ? 20 : 22,
                  color: unlocked
                      ? AppColors.gold
                      : inProgress
                          ? AppColors.silver
                          : AppColors.textTertiary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.achievement.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            unlocked
                ? '${item.achievement.requiredValue} ${_unit(item.achievement.type)}'
                : '${item.progress}/${item.achievement.requiredValue}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 10.5,
                ),
          ),
        ],
      ),
    );
  }

  String _unit(String type) {
    switch (type) {
      case 'wins':
        return 'побед';
      case 'events_count':
        return 'мер.';
      case 'polygons_visited':
        return 'пол.';
      default:
        return 'игр';
    }
  }

  IconData _iconFor(String icon) {
    switch (icon) {
      case 'veteran':
        return Icons.military_tech;
      case 'tactician':
        return Icons.psychology_alt;
      case 'master':
        return Icons.workspace_premium;
      case 'teammate':
        return Icons.groups;
      case 'traveler':
        return Icons.explore;
      case 'first_event':
        return Icons.flag;
      case 'activist':
        return Icons.local_activity;
      case 'community_veteran':
        return Icons.shield;
      default:
        return Icons.emoji_events;
    }
  }
}

class _HexBadgePainter extends CustomPainter {
  _HexBadgePainter({
    required this.fill,
    required this.stroke,
    required this.strokeWidth,
  });

  final Color fill;
  final Color stroke;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _hex(size);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  Path _hex(Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = math.min(size.width, size.height) / 2 - 1;
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = (math.pi / 180) * (60 * i - 30);
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _HexBadgePainter oldDelegate) {
    return oldDelegate.fill != fill ||
        oldDelegate.stroke != stroke ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
