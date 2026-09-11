import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_layout.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../data/repositories/profile_photo_repository.dart';
import '../../../domain/models/profile.dart';
import '../../../domain/models/user_achievement_progress.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../presentation/providers/clan_providers.dart';
import '../../../presentation/providers/profile_providers.dart';
import '../../../presentation/providers/ranking_providers.dart';
import '../../../presentation/providers/organizer_wallet_providers.dart';
import '../../../presentation/providers/repository_providers.dart';
import '../../../domain/models/ranking.dart';
import '../../../services/achievement_service.dart';
import '../../../services/level_service.dart';
import '../../../widgets/achievement_card.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_network_image.dart';
import '../../../widgets/app_page_body.dart';
import '../../../widgets/feedback.dart';
import '../../../widgets/level_progress_bar.dart';
import '../../../widgets/level_up_overlay.dart';
import '../../../widgets/photo_lightbox.dart';
import '../../../widgets/role_badge.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  int? _levelUpTo;

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);
    final level = ref.watch(levelProgressProvider);
    final achievementsAsync = ref.watch(achievementsProvider);
    final achievementService = ref.watch(achievementServiceProvider);
    final eventsCount = ref.watch(userEventsCountProvider).valueOrNull ?? 0;

    ref.listen(levelProgressProvider, (previous, next) {
      final profile = ref.read(currentProfileProvider).valueOrNull;
      if (profile == null) return;

      // Wait until events count is known so XP isn't undercounted.
      final eventsAsync = ref.read(userEventsCountProvider);
      if (!eventsAsync.hasValue) return;

      final stored = ref.read(previousLevelProvider);
      if (stored != null && next.currentLevel > stored) {
        setState(() => _levelUpTo = next.currentLevel);
        ref.read(previousLevelProvider.notifier).state = next.currentLevel;
        return;
      }

      // Initialize or keep the highest known level — never regress on
      // transient recalculations (profile/events loading flash).
      if (stored == null || next.currentLevel > stored) {
        ref.read(previousLevelProvider.notifier).state = next.currentLevel;
      }
    });

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leadingWidth: AppLayout.isCompact(context) ? 72 : 88,
        leading: TextButton(
          onPressed: () {
            ref.read(rankingEntityTabProvider.notifier).state =
                RankingEntityTab.players;
            ref.read(rankingScopeTabProvider.notifier).state =
                RankingScopeTab.global;
            ref.read(rankingHighlightMeProvider.notifier).state = true;
            context.push('/main/profile/rating');
          },
          style: TextButton.styleFrom(
            foregroundColor: AppColors.accent,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: const Text(
              'Рейтинг',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
            ),
          ),
        ),
        title: const Text('Боевой паспорт'),
        actions: [
          TextButton(
            onPressed: () => context.push('/main/profile/dating'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.groups_outlined, size: 16),
                SizedBox(width: 4),
                Text(
                  'Дейтинг',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Редактировать',
            onPressed: () => context.push('/main/profile/edit'),
            icon: const Icon(Icons.edit_outlined, size: 18),
          ),
          IconButton(
            tooltip: 'Выйти',
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout, size: 18),
          ),
        ],
      ),
      body: Stack(
        children: [
          profileAsync.when(
            skipLoadingOnReload: true,
            skipLoadingOnRefresh: true,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => AsyncErrorRetry(
              message: ErrorMapper.map(e),
              onRetry: () =>
                  ref.read(currentProfileProvider.notifier).refresh(),
            ),
            data: (profile) {
              if (profile == null) {
                return AsyncErrorRetry(
                  message: 'Профиль не найден',
                  onRetry: () =>
                      ref.read(currentProfileProvider.notifier).refresh(),
                );
              }
              return RefreshIndicator(
                color: AppColors.accent,
                onRefresh: () async {
                  await Future.wait([
                    ref
                        .read(currentProfileProvider.notifier)
                        .refresh(silent: true),
                    ref.read(userEventsCountProvider.notifier).refresh(),
                    ref.read(achievementsProvider.notifier).refresh(),
                  ]);
                },
                child: AppPageBody(
                  child: _PassportBody(
                    profile: profile,
                    level: level,
                    eventsCount: eventsCount,
                    achievements: achievementsAsync,
                    achievementService: achievementService,
                  ),
                ),
              );
            },
          ),
          if (_levelUpTo != null)
            LevelUpOverlay(
              level: _levelUpTo!,
              onFinished: () => setState(() => _levelUpTo = null),
            ),
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Выйти из аккаунта?'),
        content: const Text('Сессия будет завершена на этом устройстве.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(authControllerProvider.notifier).logout();
    if (context.mounted) context.go('/login');
  }
}

class _PassportBody extends ConsumerWidget {
  const _PassportBody({
    required this.profile,
    required this.level,
    required this.eventsCount,
    required this.achievements,
    required this.achievementService,
  });

  final Profile profile;
  final LevelProgress level;
  final int eventsCount;
  final AsyncValue<List<UserAchievementProgress>> achievements;
  final AchievementService achievementService;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(myProfilePhotosProvider).valueOrNull ?? const [];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: AppLayout.pagePadding(context),
      children: [
        _HeaderBlock(profile: profile, level: level),
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
                  Container(width: 1, height: 42, color: AppColors.borderSubtle),
                  const Expanded(child: _ClanInfoCell()),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          accentBorder: true,
          onTap: () => context.push('/main/profile/qr'),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.accentDim),
                ),
                child: const Icon(
                  Icons.qr_code_2,
                  color: AppColors.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'QR-код',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Показать организатору на мероприятии',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
        if (profile.isOrganizer) ...[
          const SizedBox(height: 10),
          const _OrganizerPassportCard(),
        ],
        const SizedBox(height: 10),
        AppCard(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle(
                title: 'Статистика',
                trailing: LinkLabel(
                  label: 'Рейтинг >',
                  onTap: () {
                    ref.read(rankingEntityTabProvider.notifier).state =
                        RankingEntityTab.players;
                    ref.read(rankingScopeTabProvider.notifier).state =
                        RankingScopeTab.global;
                    ref.read(rankingHighlightMeProvider.notifier).state = true;
                    context.push('/main/profile/rating');
                  },
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _StatCell(
                      icon: Icons.gps_fixed,
                      value: '${profile.gamesPlayed}',
                      label: 'Игр сыграно',
                    ),
                  ),
                  Container(width: 1, height: 48, color: AppColors.borderSubtle),
                  Expanded(
                    child: _StatCell(
                      icon: Icons.event_available_outlined,
                      value: '$eventsCount',
                      label: 'Мероприятия',
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
              SectionTitle(
                title: 'Достижения',
                trailing: LinkLabel(
                  label: 'Смотреть все >',
                  onTap: () => context.push('/main/profile/achievements'),
                ),
              ),
              achievements.when(
                loading: () => const SizedBox(
                  height: 88,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
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
                      'Достижения появятся после синхронизации',
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
                            state: achievementService.visualState(item),
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
              SectionTitle(
                title: 'Фото',
                trailing: LinkLabel(
                  label: 'Изменить >',
                  onTap: () => context.push('/main/profile/photos'),
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  const max = ProfilePhotoRepository.maxPhotos;
                  const gap = 8.0;
                  final cell =
                      (constraints.maxWidth - gap * (max - 1)) / max;
                  return SizedBox(
                    height: cell,
                    child: Row(
                      children: [
                        for (var index = 0; index < max; index++) ...[
                          if (index > 0) const SizedBox(width: gap),
                          Expanded(
                            child: index < photos.length
                                ? Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => showPhotoLightbox(
                                        context,
                                        urls: [
                                          for (final p in photos) p.url,
                                        ],
                                        initialIndex: index,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: AppNetworkImage(
                                          url: photos[index].url,
                                          fit: BoxFit.cover,
                                          memCacheWidth: 320,
                                          showSpinner: true,
                                          debugLabel: 'profile-photo',
                                          placeholderIcon: Icons.image_outlined,
                                        ),
                                      ),
                                    ),
                                  )
                                : Material(
                                    color: AppColors.surfaceElevated,
                                    borderRadius: BorderRadius.circular(10),
                                    child: InkWell(
                                      onTap: () => context
                                          .push('/main/profile/photos'),
                                      borderRadius: BorderRadius.circular(10),
                                      child: const Center(
                                        child: Icon(
                                          Icons.add,
                                          color: AppColors.accent,
                                          size: 20,
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
              const SizedBox(height: 6),
              Text(
                '${photos.length} / ${ProfilePhotoRepository.maxPhotos}',
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeaderBlock extends StatelessWidget {
  const _HeaderBlock({required this.profile, required this.level});

  final Profile profile;
  final LevelProgress level;

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
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                fontSize: 13.5,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _Emblem(gameRole: profile.parsedGameRole),
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

    return Stack(
      children: [
        Container(
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
                  memCacheHeight: 200,
                  debugLabel: 'profile-avatar',
                  placeholderIcon: Icons.person_outline,
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
        ),
        Positioned(
          right: 2,
          bottom: 2,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.card, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _Emblem extends StatelessWidget {
  const _Emblem({this.gameRole});

  final GameRole? gameRole;

  @override
  Widget build(BuildContext context) {
    final icon = gameRole != null ? gameRoleIcon(gameRole!) : Icons.shield;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF231F12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.55)),
      ),
      child: Icon(icon, color: AppColors.gold, size: 22),
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

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.icon,
    required this.value,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: onTap != null ? AppColors.accent : null,
                      ),
                ),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                      ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            const Icon(
              Icons.chevron_right,
              size: 16,
              color: AppColors.textTertiary,
            ),
        ],
      ),
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: content,
    );
  }
}

class _ClanInfoCell extends ConsumerWidget {
  const _ClanInfoCell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clan = ref.watch(myClanProvider).valueOrNull;
    return InkWell(
      onTap: () {
        if (clan == null) {
          context.push('/main/profile/clans');
        } else {
          context.push('/main/profile/clan/${clan.id}');
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: _InfoCell(
        icon: Icons.shield_outlined,
        label: 'Клан',
        value: clan == null ? 'Без клана' : clan.name,
      ),
    );
  }
}

class _OrganizerPassportCard extends ConsumerWidget {
  const _OrganizerPassportCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(organizerWalletProvider).valueOrNull;

    return AppCard(
      accentBorder: true,
      onTap: () => context.push('/main/profile/organizer'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.accentDim),
            ),
            child: const Icon(
              Icons.badge_outlined,
              color: AppColors.accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Организатор',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Баланс: ${wallet?.balanceLabel ?? '0 CR'}',
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Мероприятия · сканер · баланс',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            size: 18,
            color: AppColors.textTertiary,
          ),
        ],
      ),
    );
  }
}
