import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../domain/models/profile.dart';

class RoleBadge extends StatelessWidget {
  const RoleBadge({
    super.key,
    required this.role,
    this.compact = false,
  });

  final ProfileBadgeRole role;
  final bool compact;

  Color get _color => switch (role) {
        ProfileBadgeRole.admin => AppColors.roleAdmin,
        ProfileBadgeRole.moderator => AppColors.roleModerator,
        ProfileBadgeRole.organizer => AppColors.roleOrganizer,
        ProfileBadgeRole.user => AppColors.roleUser,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadii.badge),
        border: Border.all(color: _color.withValues(alpha: 0.55)),
      ),
      child: Text(
        role.labelRu,
        style: TextStyle(
          color: _color,
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}
