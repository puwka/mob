import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import 'app_card.dart';

/// Back-compat alias used by older screens.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(title: title, trailing: trailing),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }
}

class AccentChip extends StatelessWidget {
  const AccentChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppRadii.chip),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.accent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
