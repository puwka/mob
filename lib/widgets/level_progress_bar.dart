import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../services/level_service.dart';

class LevelProgressBar extends StatelessWidget {
  const LevelProgressBar({
    super.key,
    required this.progress,
    this.showMeta = true,
  });

  final LevelProgress progress;
  final bool showMeta;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showMeta)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Text(
                  'Уровень ${progress.currentLevel}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.accent,
                        fontSize: 14,
                      ),
                ),
                const Spacer(),
                Text(
                  '${progress.xpIntoLevel}/${progress.xpForNextLevel} XP',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                      ),
                ),
              ],
            ),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progress.progress,
            minHeight: 5,
            backgroundColor: AppColors.border,
            color: AppColors.accent,
          ),
        ),
      ],
    );
  }
}
