import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../data/repositories/profile_photo_repository.dart';
import '../../../domain/models/conversation.dart';
import '../../../domain/models/profile.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../presentation/providers/chat_providers.dart';
import '../../../presentation/providers/clan_providers.dart';
import '../../../presentation/providers/presence_providers.dart';
import '../../../presentation/providers/profile_providers.dart';
import '../../../presentation/providers/repository_providers.dart';
import '../../../services/level_service.dart';
import '../../../widgets/achievement_card.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_network_image.dart';
import '../../../widgets/feedback.dart';
import '../../../widgets/level_progress_bar.dart';
import '../../../widgets/photo_lightbox.dart';
import '../../../widgets/presence_status.dart';
import '../../../widgets/role_badge.dart';

/// Public passport view — same layout as own profile, without QR / stats.
class UserProfileScreen extends ConsumerWidget {
  const UserProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(profileByIdProvider(userId));
    final me = ref.watch(currentUserProvider)?.id;
    final isSelf = me == userId;
    final clanAsync = ref.watch(clanForUserProvider(userId));
    final photosAsync = ref.watch(profilePhotosProvider(userId));
    final achievementsAsync = ref.watch(userAchievementsByIdProvider(userId));
    final achievementService = ref.watch(achievementServiceProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(isSelf ? 'Боевой паспорт' : 'Профиль бойца'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncErrorRetry(
          message: ErrorMapper.map(e),
          onRetry: () => ref.invalidate(profileByIdProvider(userId)),
        ),
        data: (profile) {
          if (profile == null) {
            return const Center(
              child: Text(
                'Профиль не найден',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            );
          }

          final level = ref.watch(levelProgressForProfileProvider(profile));
          final photos = photosAsync.valueOrNull ?? const [];

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _PublicHeader(
                profile: profile,
                level: level,
                lastSeenAt: ref.watch(userLastSeenProvider(userId)).valueOrNull ??
                    profile.lastSeenAt,
              ),
              const SizedBox(height: 12),
              AppCard(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle(title: 'Игровая информация'),
                    Row(
                      children: [
                        Expanded(
                          child: _InfoCell(
                            icon: Icons.sports_martial_arts_outlined,
                            label: 'Класс',
                            value: profile.gameRoleLabel,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 42,
                          color: AppColors.borderSubtle,
                        ),
                        Expanded(
                          child: clanAsync.when(
                            loading: () => const _InfoCell(
                              icon: Icons.shield_outlined,
                              label: 'Клан',
                              value: '…',
                            ),
                            error: (_, _) => const _InfoCell(
                              icon: Icons.shield_outlined,
                              label: 'Клан',
                              value: 'Без клана',
                            ),
                            data: (clan) => InkWell(
                              onTap: clan == null
                                  ? null
                                  : () => context.push(
                                        '/main/profile/clan/${clan.id}',
                                      ),
                              borderRadius: BorderRadius.circular(8),
                              child: _InfoCell(
                                icon: Icons.shield_outlined,
                                label: 'Клан',
                                value: clan?.name ?? 'Без клана',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              AppCard(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle(title: 'Достижения'),
                    achievementsAsync.when(
                      loading: () => const SizedBox(
                        height: 88,
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      error: (e, _) => Text(
                        ErrorMapper.map(e),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.danger,
                            ),
                      ),
                      data: (items) {
                        if (items.isEmpty) {
                          return Text(
                            'Достижений пока нет',
                            style: Theme.of(context).textTheme.bodySmall,
                          );
                        }
                        final preview = items.take(5).toList();
                        return SizedBox(
                          height: 108,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: preview.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(width: 10),
                            itemBuilder: (context, index) {
                              final item = preview[index];
                              return SizedBox(
                                width: 72,
                                child: AchievementCard(
                                  item: item,
                                  state:
                                      achievementService.visualState(item),
                                  compact: true,
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              AppCard(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Фото · ${photos.length} / ${ProfilePhotoRepository.maxPhotos}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            fontSize: 11,
                          ),
                    ),
                    const SizedBox(height: 10),
                    if (photos.isEmpty)
                      Text(
                        'Галерея пуста',
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    else
                      LayoutBuilder(
                        builder: (context, constraints) {
                          const max = ProfilePhotoRepository.maxPhotos;
                          const gap = 8.0;
                          final count = photos.length.clamp(1, max);
                          final cell =
                              (constraints.maxWidth - gap * (count - 1)) /
                                  count;
                          return SizedBox(
                            height: cell,
                            child: Row(
                              children: [
                                for (var i = 0; i < count; i++) ...[
                                  if (i > 0) const SizedBox(width: gap),
                                  Expanded(
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () => showPhotoLightbox(
                                          context,
                                          urls: [
                                            for (final p in photos) p.url,
                                          ],
                                          initialIndex: i,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          child: AppNetworkImage(
                                            url: photos[i].url,
                                            fit: BoxFit.cover,
                                            memCacheWidth: 320,
                                            showSpinner: true,
                                            debugLabel: 'user-photo',
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
              if (!isSelf) ...[
                const SizedBox(height: 16),
                AppButton(
                  label: 'Написать',
                  onPressed: () => _message(context, ref, userId),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _message(
    BuildContext context,
    WidgetRef ref,
    String otherUserId,
  ) async {
    try {
      final id =
          await ref.read(chatRepositoryProvider).openUserChat(otherUserId);
      ref.read(chatFolderProvider.notifier).state = ConversationType.user;
      if (context.mounted) context.go('/main/chats/$id');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorMapper.map(e))),
        );
      }
    }
  }
}

class _PublicHeader extends StatelessWidget {
  const _PublicHeader({
    required this.profile,
    required this.level,
    this.lastSeenAt,
  });

  final Profile profile;
  final LevelProgress level;
  final DateTime? lastSeenAt;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(nickname: profile.nickname, url: profile.avatarUrl),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ProfileNameBadges(badgeRole: profile.badgeRole),
                    Text(
                      profile.nickname,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontSize: 18),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    PresenceStatusText(
                      lastSeenAt: lastSeenAt,
                      fontSize: 12.5,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 14,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          profile.city,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontSize: 13.5,
                                  ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF231F12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.55),
                  ),
                ),
                child: Icon(
                  profile.parsedGameRole != null
                      ? gameRoleIcon(profile.parsedGameRole!)
                      : Icons.shield,
                  color: AppColors.gold,
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: LevelProgressBar(progress: level)),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(AppRadii.chip),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  'Уровень ${level.currentLevel}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.nickname, this.url});

  final String nickname;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final letter = nickname.isNotEmpty ? nickname[0].toUpperCase() : '?';
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceElevated,
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null && url!.isNotEmpty
          ? AppNetworkImage(
              url: url,
              fit: BoxFit.cover,
              width: 88,
              height: 88,
              memCacheWidth: 200,
              showSpinner: false,
              debugLabel: 'user-avatar',
            )
          : Center(
              child: Text(
                letter,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
    );
  }
}

class _InfoCell extends StatelessWidget {
  const _InfoCell({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                      ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 14,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
