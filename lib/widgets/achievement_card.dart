import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../domain/models/achievement.dart';
import '../domain/models/user_achievement_progress.dart';
import '../services/achievement_service.dart';
import 'app_network_image.dart';

enum AchievementCategory {
  all,
  social,
  game,
  growth,
  other;

  String get labelRu => switch (this) {
        AchievementCategory.all => 'Все',
        AchievementCategory.social => 'Общение',
        AchievementCategory.game => 'Игра',
        AchievementCategory.growth => 'Развитие',
        AchievementCategory.other => 'Другое',
      };

  static AchievementCategory fromType(String type) {
    switch (type) {
      case AchievementTypes.messagesSent:
      case AchievementTypes.datingLikes:
        return AchievementCategory.social;
      case AchievementTypes.gamesPlayed:
      case AchievementTypes.wins:
      case AchievementTypes.eventsCount:
      case AchievementTypes.eventsAttendedConfirmed:
      case AchievementTypes.teamGames:
      case AchievementTypes.roleGames:
      case AchievementTypes.polygonsVisited:
        return AchievementCategory.game;
      case AchievementTypes.rating:
      case AchievementTypes.profilePhotos:
      case AchievementTypes.clanJoined:
        return AchievementCategory.growth;
      default:
        return AchievementCategory.other;
    }
  }
}

/// Compact badge used on the profile preview row.
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

    final iconSize = compact ? 22.0 : 26.0;
    final iconColor = unlocked
        ? AppColors.gold
        : inProgress
            ? AppColors.silver
            : AppColors.textTertiary;

    return Opacity(
      opacity: state == AchievementVisualState.locked ? 0.55 : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AchievementHexBadge(
            size: compact ? 52 : 58,
            fill: fill,
            stroke: badgeColor,
            strokeWidth: unlocked ? 1.6 : 1.1,
            child: AchievementGlyph(
              icon: item.achievement.icon,
              size: iconSize,
              color: iconColor,
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
                ? '${item.achievement.requiredValue}'
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
}

/// Catalog tile matching the achievements screen mockup.
class AchievementCatalogCard extends StatelessWidget {
  const AchievementCatalogCard({
    super.key,
    required this.item,
    required this.state,
    this.onTap,
  });

  final UserAchievementProgress item;
  final AchievementVisualState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final unlocked = state == AchievementVisualState.unlocked;
    final inProgress = state == AchievementVisualState.progress;
    final locked = state == AchievementVisualState.locked;

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
    final iconColor = unlocked
        ? AppColors.gold
        : inProgress
            ? AppColors.silver
            : AppColors.textTertiary;

    final required = item.achievement.requiredValue;
    final progress = unlocked ? required : item.progress;
    final ratio = required == 0 ? 1.0 : (progress / required).clamp(0.0, 1.0);

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Opacity(
            opacity: locked ? 0.72 : 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: AppColors.textTertiary.withValues(alpha: 0.8),
                    ),
                  ),
                  Center(
                    child: AchievementHexBadge(
                      size: 56,
                      fill: fill,
                      stroke: badgeColor,
                      strokeWidth: unlocked ? 1.7 : 1.2,
                      child: locked && progress == 0
                          ? Center(
                              child: Icon(
                                Icons.lock_outline,
                                size: 22,
                                color: iconColor,
                              ),
                            )
                          : AchievementGlyph(
                              icon: item.achievement.icon,
                              size: 26,
                              color: iconColor,
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item.achievement.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Text(
                      item.achievement.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10.5,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$progress / $required',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: unlocked ? AppColors.gold : AppColors.textTertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.achievement.rewardXp > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      '+${item.achievement.rewardXp} XP',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: unlocked
                            ? AppColors.accent
                            : AppColors.textTertiary.withValues(alpha: 0.75),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: ratio.toDouble(),
                      minHeight: 8,
                      backgroundColor: AppColors.surfaceElevated,
                      color: unlocked
                          ? AppColors.gold
                          : inProgress
                              ? AppColors.silver
                              : AppColors.border,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AchievementHexBadge extends StatelessWidget {
  const AchievementHexBadge({
    super.key,
    required this.size,
    required this.fill,
    required this.stroke,
    required this.strokeWidth,
    required this.child,
  });

  final double size;
  final Color fill;
  final Color stroke;
  final double strokeWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final h = size * 1.1;
    return SizedBox(
      width: size,
      height: h,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipPath(
            clipper: AchievementHexClipper(),
            child: ColoredBox(
              color: fill,
              child: child,
            ),
          ),
          CustomPaint(
            painter: AchievementHexPainter(
              fill: Colors.transparent,
              stroke: stroke,
              strokeWidth: strokeWidth,
            ),
          ),
        ],
      ),
    );
  }
}

class AchievementGlyph extends StatelessWidget {
  const AchievementGlyph({
    super.key,
    required this.icon,
    required this.size,
    required this.color,
  });

  final String icon;
  final double size;
  final Color color;

  static bool isImageUrl(String value) {
    final lower = value.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  @override
  Widget build(BuildContext context) {
    if (isImageUrl(icon)) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth.isFinite && constraints.maxWidth > 0
              ? constraints.maxWidth
              : size * 2;
          final h = constraints.maxHeight.isFinite && constraints.maxHeight > 0
              ? constraints.maxHeight
              : size * 2.2;
          return AppNetworkImage(
            url: icon,
            width: w,
            height: h,
            fit: BoxFit.cover,
            memCacheWidth: (w * 3).round().clamp(128, 512),
            placeholderIcon: Icons.emoji_events,
            errorIcon: Icons.emoji_events,
            backgroundColor: Colors.transparent,
            iconSize: size * 0.7,
            showSpinner: false,
            debugLabel: 'achievement-icon',
          );
        },
      );
    }

    return Center(
      child: Icon(_iconFor(icon), size: size * 0.85, color: color),
    );
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

Path achievementHexPath(Size size) {
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

class AchievementHexClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => achievementHexPath(size);

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class AchievementHexPainter extends CustomPainter {
  AchievementHexPainter({
    required this.fill,
    required this.stroke,
    required this.strokeWidth,
  });

  final Color fill;
  final Color stroke;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final path = achievementHexPath(size);
    if (fill.a > 0) {
      canvas.drawPath(path, Paint()..color = fill);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant AchievementHexPainter oldDelegate) {
    return oldDelegate.fill != fill ||
        oldDelegate.stroke != stroke ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
