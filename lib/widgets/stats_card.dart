import 'package:flutter/material.dart';

import '../core/layout/app_layout.dart';
import '../core/theme/app_colors.dart';
import 'app_card.dart';

class StatsCard extends StatelessWidget {
  const StatsCard({
    super.key,
    required this.gamesPlayed,
    required this.wins,
    required this.rating,
    this.polygonsVisited,
    this.eventsCount,
  });

  final int gamesPlayed;
  final int wins;
  final int rating;
  final int? polygonsVisited;
  final int? eventsCount;

  @override
  Widget build(BuildContext context) {
    final valueSize = AppLayout.statsValueFont(context);
    final compact = AppLayout.isCompact(context);

    return AppCard(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 6,
        vertical: compact ? 12 : 16,
      ),
      child: Row(
        children: [
          _Stat(
            label: 'Игры',
            value: '$gamesPlayed',
            icon: Icons.sports_esports_outlined,
            valueSize: valueSize,
            compact: compact,
          ),
          _Divider(compact: compact),
          _Stat(
            label: 'Победы',
            value: '$wins',
            icon: Icons.emoji_events_outlined,
            valueSize: valueSize,
            compact: compact,
          ),
          _Divider(compact: compact),
          _Stat(
            label: 'Рейтинг',
            value: '$rating',
            icon: Icons.trending_up,
            valueSize: valueSize,
            compact: compact,
          ),
          if (eventsCount != null) ...[
            _Divider(compact: compact),
            _Stat(
              label: 'Ивенты',
              value: '$eventsCount',
              icon: Icons.event_available_outlined,
              valueSize: valueSize,
              compact: compact,
            ),
          ] else if (polygonsVisited != null) ...[
            _Divider(compact: compact),
            _Stat(
              label: 'Полигоны',
              value: '$polygonsVisited',
              icon: Icons.map_outlined,
              valueSize: valueSize,
              compact: compact,
            ),
          ],
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: compact ? 36 : 44,
      color: AppColors.borderSubtle,
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.icon,
    required this.valueSize,
    required this.compact,
  });

  final String label;
  final String value;
  final IconData icon;
  final double valueSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 14 : 16, color: AppColors.accent),
          SizedBox(height: compact ? 6 : 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: valueSize,
                  ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: compact ? 10 : null,
                ),
          ),
        ],
      ),
    );
  }
}
