import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../domain/models/clan.dart';
import '../../../presentation/providers/clan_providers.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../presentation/providers/profile_providers.dart';
import '../../../presentation/providers/repository_providers.dart';
import '../../../services/level_service.dart';
import '../../../widgets/feedback.dart';

class ClanSearchScreen extends ConsumerStatefulWidget {
  const ClanSearchScreen({super.key});

  @override
  ConsumerState<ClanSearchScreen> createState() => _ClanSearchScreenState();
}

class _ClanSearchScreenState extends ConsumerState<ClanSearchScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(clanSearchProvider);
    final myClan = ref.watch(myClanProvider).valueOrNull;
    final profileCity =
        ref.watch(currentProfileProvider).valueOrNull?.city.trim() ?? '';
    final level = ref.watch(levelProgressProvider).currentLevel;
    final canCreateClan = myClan == null &&
        level >= LevelService.minLevelToCreateClan;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Кланы'),
        actions: [
          if (myClan == null)
            TextButton(
              onPressed: () {
                if (!canCreateClan) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Создать клан можно с ${LevelService.minLevelToCreateClan} уровня '
                        '(сейчас $level)',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                context.push('/main/profile/clan/create');
              },
              child: Text(
                'Создать',
                style: TextStyle(
                  color: canCreateClan
                      ? null
                      : AppColors.textTertiary,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (profileCity.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Кланы города: $profileCity',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SizedBox(
              height: 44,
              child: TextField(
                controller: _search,
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), () {
                    ref.read(clanSearchQueryProvider.notifier).state = v;
                  });
                },
                decoration: const InputDecoration(
                  hintText: 'Поиск клана по имени или TAG',
                  prefixIcon: Icon(Icons.search, size: 18),
                  isDense: true,
                ),
              ),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => AsyncErrorRetry(
                message: ErrorMapper.map(e),
                onRetry: () => ref.invalidate(clanSearchProvider),
              ),
              data: (clans) {
                if (clans.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: EmptyStateCard(
                      title: 'Кланы не найдены',
                      subtitle: profileCity.isEmpty
                          ? 'Укажите город в профиле, чтобы видеть кланы своего города.'
                          : 'В городе $profileCity пока нет кланов. Создайте свой или смотрите все в рейтинге (Общий).',
                      icon: Icons.shield_outlined,
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  itemCount: clans.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final clan = clans[index];
                    return _ClanCard(
                      clan: clan,
                      isMine: myClan?.id == clan.id,
                      onOpen: () =>
                          context.push('/main/profile/clan/${clan.id}'),
                      onApply: myClan == null
                          ? () => _apply(clan.id)
                          : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _apply(String clanId) async {
    try {
      await ref.read(clanRepositoryProvider).requestJoin(clanId);
      ref.invalidate(myJoinStatusProvider(clanId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Заявка отправлена лидеру клана'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorMapper.map(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _ClanCard extends ConsumerWidget {
  const _ClanCard({
    required this.clan,
    required this.isMine,
    required this.onOpen,
    this.onApply,
  });

  final Clan clan;
  final bool isMine;
  final VoidCallback onOpen;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = onApply == null
        ? null
        : ref.watch(myJoinStatusProvider(clan.id));
    final pending = statusAsync?.valueOrNull == ClanJoinStatus.pending;

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(
              color: isMine
                  ? AppColors.accent.withValues(alpha: 0.5)
                  : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              _ClanEmblem(url: clan.avatarUrl, tag: clan.tag, size: 48),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${clan.name} ${clan.displayTag}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (clan.city != null && clan.city!.trim().isNotEmpty)
                          clan.city!.trim(),
                        'Рейтинг ${clan.rating}',
                        '${clan.membersCount} уч.',
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (isMine)
                const Text(
                  'Ваш',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                )
              else if (onApply != null)
                TextButton(
                  onPressed: pending ? null : onApply,
                  child: Text(pending ? 'Ожидание' : 'Подать заявку'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClanEmblem extends StatelessWidget {
  const _ClanEmblem({
    required this.tag,
    this.url,
    this.size = 56,
  });

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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accentDim),
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null && url!.isNotEmpty
          ? Image.network(url!, fit: BoxFit.cover)
          : Center(
              child: Text(
                tag.length > 3 ? tag.substring(0, 3) : tag,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
    );
  }
}
