import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../domain/models/profile.dart';

IconData gameRoleIcon(GameRole role) => switch (role) {
      GameRole.assault => Icons.sports_martial_arts,
      GameRole.sniper => Icons.center_focus_strong,
      GameRole.medic => Icons.medical_services_outlined,
      GameRole.recon => Icons.visibility_outlined,
      GameRole.support => Icons.bolt_outlined,
      GameRole.marksman => Icons.track_changes,
      GameRole.grenadier => Icons.local_fire_department_outlined,
    };

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
        ProfileBadgeRole.sherpa => AppColors.roleSherpa,
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

/// In-game role chip with icon (assault / sniper / …).
class GameRoleBadge extends StatelessWidget {
  const GameRoleBadge({
    super.key,
    required this.role,
    this.compact = false,
  });

  final GameRole role;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadii.badge),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            gameRoleIcon(role),
            size: compact ? 12 : 13,
            color: AppColors.accent,
          ),
          SizedBox(width: compact ? 3 : 4),
          Text(
            role.labelRu,
            style: TextStyle(
              color: AppColors.accent,
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Privilege/status badge near the nickname (admin / moderator / …).
/// Game class is shown as the emblem icon on the right, not as a chip.
class ProfileNameBadges extends StatelessWidget {
  const ProfileNameBadges({
    super.key,
    required this.badgeRole,
    this.compact = false,
  });

  final ProfileBadgeRole badgeRole;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!badgeRole.isPrivileged) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RoleBadge(role: badgeRole, compact: compact),
    );
  }
}
