import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../domain/models/conversation.dart';
import '../../../domain/models/profile.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../presentation/providers/chat_providers.dart';
import '../../../presentation/providers/clan_providers.dart';
import '../../../presentation/providers/presence_providers.dart';
import '../../../presentation/providers/profile_providers.dart';
import '../../../presentation/providers/repository_providers.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/feedback.dart';
import '../../../widgets/presence_status.dart';

class UserProfileScreen extends ConsumerWidget {
  const UserProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(profileByIdProvider(userId));
    final me = ref.watch(currentUserProvider)?.id;
    final isSelf = me == userId;
    final clanAsync = ref.watch(clanForUserProvider(userId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Профиль бойца'),
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

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              AppCard(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Row(
                  children: [
                    _Avatar(profile: profile, size: 64),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.nickname,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          PresenceStatusText(
                            lastSeenAt: ref
                                    .watch(userLastSeenProvider(userId))
                                    .valueOrNull ??
                                profile.lastSeenAt,
                            fontSize: 12.5,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            profile.city,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          if (profile.gameRole != null &&
                              profile.gameRole!.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              profile.gameRole!,
                              style: const TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ],
                      ),
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
                    const SectionTitle(title: 'Рейтинг'),
                    Text(
                      '${profile.rating}',
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Личный рейтинг игрока',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
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
                    const SectionTitle(title: 'Статистика'),
                    Row(
                      children: [
                        Expanded(
                          child: _Stat(
                            label: 'Игр',
                            value: '${profile.gamesPlayed}',
                          ),
                        ),
                        Expanded(
                          child: _Stat(
                            label: 'Побед',
                            value: '${profile.wins}',
                          ),
                        ),
                        Expanded(
                          child: _Stat(
                            label: 'Полигоны',
                            value: '${profile.polygonsVisited}',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              clanAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
                data: (clan) {
                  if (clan == null) {
                    return AppCard(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      child: Text(
                        'Без клана',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textTertiary,
                            ),
                      ),
                    );
                  }
                  return AppCard(
                    accentBorder: true,
                    onTap: () => context.push('/main/profile/clan/${clan.id}'),
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                            image: clan.avatarUrl != null
                                ? DecorationImage(
                                    image: NetworkImage(clan.avatarUrl!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: clan.avatarUrl == null
                              ? Text(
                                  clan.tag,
                                  style: const TextStyle(
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Клан ${clan.name}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${clan.displayTag} · рейтинг ${clan.rating}',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          color: AppColors.textTertiary,
                          size: 18,
                        ),
                      ],
                    ),
                  );
                },
              ),
              if (profile.bio != null && profile.bio!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionTitle(title: 'О себе'),
                      Text(
                        profile.bio!,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.4,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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

class _Avatar extends StatelessWidget {
  const _Avatar({required this.profile, required this.size});

  final Profile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final letter =
        profile.nickname.isNotEmpty ? profile.nickname[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceElevated,
        border: Border.all(color: AppColors.border),
        image: profile.avatarUrl != null
            ? DecorationImage(
                image: NetworkImage(profile.avatarUrl!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: profile.avatarUrl == null
          ? Text(
              letter,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: size * 0.36,
                color: AppColors.accent,
              ),
            )
          : null,
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}
