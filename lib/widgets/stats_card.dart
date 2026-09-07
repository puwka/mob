import 'package:flutter/material.dart';

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
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 16),
      child: Row(
        children: [
          _Stat(
            label: 'Игры',
            value: '$gamesPlayed',
            icon: Icons.sports_esports_outlined,
          ),
          _Divider(),
          _Stat(
            label: 'Победы',
            value: '$wins',
            icon: Icons.emoji_events_outlined,
          ),
          _Divider(),
          _Stat(
            label: 'Рейтинг',
            value: '$rating',
            icon: Icons.trending_up,
          ),
          if (eventsCount != null) ...[
            _Divider(),
            _Stat(
              label: 'Ивенты',
              value: '$eventsCount',
              icon: Icons.event_available_outlined,
            ),
          ] else if (polygonsVisited != null) ...[
            _Divider(),
            _Stat(
              label: 'Полигоны',
              value: '$polygonsVisited',
              icon: Icons.map_outlined,
            ),
          ],
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 44,
      color: AppColors.borderSubtle,
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 16, color: AppColors.accent),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 20,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
