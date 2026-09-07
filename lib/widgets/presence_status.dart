import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/presence.dart';

class PresenceStatusText extends StatelessWidget {
  const PresenceStatusText({
    super.key,
    required this.lastSeenAt,
    this.fontSize = 11,
  });

  final DateTime? lastSeenAt;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final online = Presence.isOnline(lastSeenAt);
    return Text(
      Presence.labelRu(lastSeenAt),
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        color: online ? AppColors.accent : AppColors.textTertiary,
      ),
    );
  }
}

class PresenceDot extends StatelessWidget {
  const PresenceDot({
    super.key,
    required this.online,
    this.size = 8,
  });

  final bool online;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: online ? AppColors.accent : AppColors.textTertiary,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.card, width: 1.5),
      ),
    );
  }
}
