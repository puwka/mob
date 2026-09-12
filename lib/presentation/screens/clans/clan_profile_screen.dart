import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../domain/models/clan.dart';
import '../../../domain/models/conversation.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../presentation/providers/chat_providers.dart';
import '../../../presentation/providers/clan_providers.dart';
import '../../../presentation/providers/repository_providers.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/city_picker.dart';
import '../../../widgets/feedback.dart';

class ClanProfileScreen extends ConsumerWidget {
  const ClanProfileScreen({super.key, required this.clanId});

  final String clanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clanAsync = ref.watch(clanDetailProvider(clanId));
    final membersAsync = ref.watch(clanMembersProvider(clanId));
    final myRole = ref.watch(myClanRoleProvider(clanId)).valueOrNull;
    final myId = ref.watch(authRepositoryProvider).currentUser?.id;
    final canManage = myRole?.canKickMembers ?? false;
    final canAssignRoles = myRole?.canAssignRoles ?? false;
    final canDecideJoins = myRole?.canDecideJoins ?? false;
    final assignableRoles = myRole?.assignableRoles ?? const <ClanRole>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Клан'),
        actions: [
          if (myRole != null)
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'chat') {
                  try {
                    final id = await ref
                        .read(chatRepositoryProvider)
                        .openClanChat(clanId);
                    ref.read(chatFolderProvider.notifier).state =
                        ConversationType.clan;
                    if (context.mounted) context.go('/main/chats/$id');
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(ErrorMapper.map(e))),
                      );
                    }
                  }
                } else if (value == 'leave') {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: AppColors.surface,
                      title: const Text('Покинуть клан?'),
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
                  if (ok == true) {
                    try {
                      await ref.read(clanRepositoryProvider).leaveClan();
                      await ref.read(myClanProvider.notifier).refresh();
                      if (context.mounted) context.go('/main/profile');
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(ErrorMapper.map(e))),
                        );
                      }
                    }
                  }
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'chat', child: Text('Клановой чат')),
                const PopupMenuItem(value: 'leave', child: Text('Покинуть')),
              ],
            ),
        ],
      ),
      body: clanAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncErrorRetry(
          message: ErrorMapper.map(e),
          onRetry: () =>
              ref.read(clanDetailProvider(clanId).notifier).refresh(),
        ),
        data: (clan) {
          return RefreshIndicator(
            color: AppColors.accent,
            onRefresh: () async {
              await ref.read(clanDetailProvider(clanId).notifier).refresh();
              ref.invalidate(clanMembersProvider(clanId));
              ref.invalidate(clanPendingRequestsProvider(clanId));
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Row(
                  children: [
                    _Emblem(url: clan.avatarUrl, tag: clan.tag, size: 72),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            clan.name,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(fontSize: 22),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            clan.displayTag,
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _StatTile(
                        label: 'РЕЙТИНГ',
                        value: clan.ratingLabel,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatTile(
                        label: 'УЧАСТНИКОВ',
                        value: '${clan.membersCount}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _StatTile(
                  label: 'ЛИДЕР',
                  value: clan.leaderNickname ?? '—',
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: myRole == ClanRole.leader
                      ? () async {
                          final selected = await showCityPicker(
                            context,
                            selected: clan.city,
                          );
                          if (selected == null || !context.mounted) return;
                          try {
                            final updated = await ref
                                .read(clanRepositoryProvider)
                                .updateClanInfo(
                                  clanId: clanId,
                                  city: selected,
                                );
                            ref
                                .read(clanDetailProvider(clanId).notifier)
                                .apply(updated);
                            ref.invalidate(myClanProvider);
                            ref.invalidate(clanSearchProvider);
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(ErrorMapper.map(e))),
                              );
                            }
                          }
                        }
                      : null,
                  borderRadius: BorderRadius.circular(10),
                  child: _StatTile(
                    label: myRole == ClanRole.leader
                        ? 'МЕСТОПОЛОЖЕНИЕ · ИЗМЕНИТЬ'
                        : 'МЕСТОПОЛОЖЕНИЕ',
                    value: (clan.city != null && clan.city!.trim().isNotEmpty)
                        ? clan.city!.trim()
                        : '—',
                  ),
                ),
                if (clan.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const SectionTitle(title: 'Описание'),
                  Text(
                    clan.description,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
                if (canDecideJoins) ...[
                  const SizedBox(height: 16),
                  const SectionTitle(title: 'Заявки'),
                  _RequestsBlock(clanId: clanId),
                ],
                if (myRole == null) ...[
                  const SizedBox(height: 16),
                  _JoinButton(clanId: clanId),
                ],
                const SizedBox(height: 16),
                const SectionTitle(title: 'Участники'),
                membersAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Text(ErrorMapper.map(e)),
                  data: (members) {
                    if (members.isEmpty) {
                      return const Text('Пока нет участников');
                    }
                    return Column(
                      children: [
                        for (final m in members)
                          _MemberRow(
                            member: m,
                            canKick: canManage &&
                                m.userId != myId &&
                                m.role != ClanRole.leader &&
                                !(myRole == ClanRole.officer &&
                                    (m.role == ClanRole.officer ||
                                        m.role == ClanRole.leader)),
                            canAssignRole: canAssignRoles &&
                                assignableRoles.isNotEmpty &&
                                m.userId != myId &&
                                m.role != ClanRole.leader &&
                                !(myRole == ClanRole.officer &&
                                    m.role == ClanRole.officer),
                            assignableRoles: assignableRoles,
                            onKick: () async {
                              try {
                                await ref
                                    .read(clanRepositoryProvider)
                                    .kickMember(m.userId);
                                ref.invalidate(clanMembersProvider(clanId));
                                await ref
                                    .read(clanDetailProvider(clanId).notifier)
                                    .refresh();
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(ErrorMapper.map(e)),
                                    ),
                                  );
                                }
                              }
                            },
                            onAssignRole: (role) async {
                              try {
                                await ref
                                    .read(clanRepositoryProvider)
                                    .setMemberRole(
                                      userId: m.userId,
                                      role: role,
                                    );
                                ref.invalidate(clanMembersProvider(clanId));
                                ref.invalidate(myClanRoleProvider(clanId));
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(ErrorMapper.map(e)),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _JoinButton extends ConsumerWidget {
  const _JoinButton({required this.clanId});

  final String clanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(myJoinStatusProvider(clanId)).valueOrNull;
    final myClan = ref.watch(myClanProvider).valueOrNull;
    if (myClan != null) return const SizedBox.shrink();

    if (status == ClanJoinStatus.pending) {
      return const AppButton(
        label: 'Заявка отправлена',
        onPressed: null,
        variant: AppButtonVariant.secondary,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          label: 'Подать заявку',
          onPressed: () async {
            try {
              await ref.read(clanRepositoryProvider).requestJoin(clanId);
              ref.invalidate(myJoinStatusProvider(clanId));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Заявка отправлена лидеру клана'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ErrorMapper.map(e))),
                );
              }
            }
          },
        ),
        const SizedBox(height: 8),
        const Text(
          'Вступление только по заявке. Решение принимает создатель клана.',
          style: TextStyle(
            color: AppColors.textTertiary,
            fontSize: 12.5,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _RequestsBlock extends ConsumerWidget {
  const _RequestsBlock({required this.clanId});

  final String clanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(clanPendingRequestsProvider(clanId));
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (requests) {
        if (requests.isEmpty) {
          return const Text(
            'Нет новых заявок',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
          );
        }
        return Column(
          children: [
            for (final r in requests)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => context.push(
                          '/main/profile/user/${r.userId}',
                        ),
                        borderRadius: BorderRadius.circular(8),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: AppColors.surfaceElevated,
                              backgroundImage: r.avatarUrl != null
                                  ? NetworkImage(r.avatarUrl!)
                                  : null,
                              child: r.avatarUrl == null
                                  ? Text(
                                      (r.nickname ?? '?')[0].toUpperCase(),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${r.nickname ?? 'Боец'} · ${r.rating}',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
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
                    ),
                    TextButton(
                      onPressed: () async {
                        await ref.read(clanRepositoryProvider).decideJoin(
                              requestId: r.id,
                              approve: true,
                            );
                        ref.invalidate(clanPendingRequestsProvider(clanId));
                        ref.invalidate(clanMembersProvider(clanId));
                        await ref
                            .read(clanDetailProvider(clanId).notifier)
                            .refresh();
                      },
                      child: const Text('Принять'),
                    ),
                    TextButton(
                      onPressed: () async {
                        await ref.read(clanRepositoryProvider).decideJoin(
                              requestId: r.id,
                              approve: false,
                            );
                        ref.invalidate(clanPendingRequestsProvider(clanId));
                      },
                      child: const Text(
                        'Отклонить',
                        style: TextStyle(color: AppColors.danger),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.canKick,
    required this.canAssignRole,
    required this.assignableRoles,
    required this.onKick,
    required this.onAssignRole,
  });

  final ClanMember member;
  final bool canKick;
  final bool canAssignRole;
  final List<ClanRole> assignableRoles;
  final VoidCallback onKick;
  final ValueChanged<ClanRole> onAssignRole;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/main/profile/user/${member.userId}'),
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.surfaceElevated,
                backgroundImage: member.avatarUrl != null
                    ? NetworkImage(member.avatarUrl!)
                    : null,
                child: member.avatarUrl == null
                    ? Text(member.nickname[0].toUpperCase())
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.nickname,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      member.role.labelRu,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${member.rating}',
                style: const TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              if (canAssignRole)
                PopupMenuButton<ClanRole>(
                  tooltip: 'Должность',
                  onSelected: onAssignRole,
                  itemBuilder: (context) => [
                    for (final role in assignableRoles)
                      PopupMenuItem(
                        value: role,
                        enabled: role != member.role,
                        child: Text(role.labelRu),
                      ),
                  ],
                  icon: const Icon(
                    Icons.badge_outlined,
                    size: 18,
                    color: AppColors.accent,
                  ),
                ),
              if (canKick)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onKick,
                  icon: const Icon(
                    Icons.person_remove_outlined,
                    size: 18,
                    color: AppColors.danger,
                  ),
                ),
              if (!canKick && !canAssignRole)
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              letterSpacing: 0.8,
              color: AppColors.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Emblem extends StatelessWidget {
  const _Emblem({required this.tag, this.url, this.size = 72});

  final String? url;
  final String tag;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accentDim, width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null && url!.isNotEmpty
          ? Image.network(url!, fit: BoxFit.cover)
          : Center(
              child: Text(
                tag,
                style: TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: size * 0.22,
                ),
              ),
            ),
    );
  }
}
