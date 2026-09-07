import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../domain/models/ranking.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../presentation/providers/ranking_providers.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/feedback.dart';

class RankingScreen extends ConsumerStatefulWidget {
  const RankingScreen({super.key});

  @override
  ConsumerState<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends ConsumerState<RankingScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels < _scroll.position.maxScrollExtent - 240) {
      return;
    }
    final entity = ref.read(rankingEntityTabProvider);
    if (entity == RankingEntityTab.players) {
      ref.read(rankingPlayersProvider.notifier).loadMore();
    } else {
      ref.read(rankingClansProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final entity = ref.watch(rankingEntityTabProvider);
    final scope = ref.watch(rankingScopeTabProvider);
    final city = ref.watch(currentProfileProvider).valueOrNull?.city;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Рейтинг',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontSize: 18,
                          ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.go('/main/profile'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: const Text(
                      'Профиль',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _SegmentRow(
                items: const [
                  (RankingEntityTab.players, 'Игроки'),
                  (RankingEntityTab.clans, 'Кланы'),
                ],
                selected: entity,
                onSelect: (v) =>
                    ref.read(rankingEntityTabProvider.notifier).state = v,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _SegmentRow(
                items: [
                  (
                    RankingScopeTab.regional,
                    city == null || city.isEmpty ? 'Областной' : city,
                  ),
                  (RankingScopeTab.global, 'Общий'),
                ],
                selected: scope,
                onSelect: (v) =>
                    ref.read(rankingScopeTabProvider.notifier).state = v,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: entity == RankingEntityTab.players
                  ? _PlayersBody(scrollController: _scroll)
                  : _ClansBody(scrollController: _scroll),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentRow<T> extends StatelessWidget {
  const _SegmentRow({
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  final List<(T, String)> items;
  final T selected;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadii.chip),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: GestureDetector(
                onTap: () => onSelect(item.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected == item.$1
                        ? AppColors.accentSoft
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadii.badge),
                    border: Border.all(
                      color: selected == item.$1
                          ? AppColors.accentDim
                          : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    item.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: selected == item.$1
                          ? AppColors.accent
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlayersBody extends ConsumerWidget {
  const _PlayersBody({required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rankingPlayersProvider);
    final myId = ref.watch(currentUserProvider)?.id;
    final highlightMe = ref.watch(rankingHighlightMeProvider);

    return async.when(
      loading: () => const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (e, _) => Center(
        child: AsyncErrorRetry(
          message: ErrorMapper.map(e),
          onRetry: () => ref.read(rankingPlayersProvider.notifier).refresh(),
        ),
      ),
      data: (state) {
        final top = _orderedTop3(state.top3);
        final list = state.listFrom4;
        final showMine = state.myEntry != null &&
            (state.myEntry!.rank > 3 ||
                !state.items.any((e) => e.id == state.myEntry!.id));

        return Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                color: AppColors.accent,
                onRefresh: () =>
                    ref.read(rankingPlayersProvider.notifier).refresh(),
                child: ListView(
                  controller: scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  children: [
                    if (top.isNotEmpty) ...[
                      _PlayersPodium(
                        entries: top,
                        onTap: (id) =>
                            context.push('/main/profile/rating/user/$id'),
                      ),
                      const SizedBox(height: 14),
                    ],
                    const SectionTitle(title: 'Список игроков'),
                    if (list.isEmpty && top.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: EmptyStateCard(
                          title: 'Пока пусто',
                          subtitle: 'В этом рейтинге ещё нет игроков.',
                        ),
                      )
                    else
                      for (final e in list) ...[
                        _PlayerRow(
                          entry: e,
                          highlight: e.id == myId,
                          onTap: () =>
                              context.push('/main/profile/rating/user/${e.id}'),
                        ),
                        const SizedBox(height: 6),
                      ],
                    if (state.hasMore)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (state.myEntry != null)
              _StickyPlayerCard(
                entry: state.myEntry!,
                emphasize: highlightMe ||
                    showMine ||
                    state.myEntry!.rank > 3,
                onTap: () => context.push(
                  '/main/profile/rating/user/${state.myEntry!.id}',
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ClansBody extends ConsumerWidget {
  const _ClansBody({required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rankingClansProvider);

    return async.when(
      loading: () => const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (e, _) => Center(
        child: AsyncErrorRetry(
          message: ErrorMapper.map(e),
          onRetry: () => ref.read(rankingClansProvider.notifier).refresh(),
        ),
      ),
      data: (state) {
        final top = _orderedTop3Clans(state.top3);
        final list = state.listFrom4;

        return Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                color: AppColors.accent,
                onRefresh: () =>
                    ref.read(rankingClansProvider.notifier).refresh(),
                child: ListView(
                  controller: scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  children: [
                    if (top.isNotEmpty) ...[
                      _ClansPodium(
                        entries: top,
                        onTap: (id) =>
                            context.push('/main/profile/rating/clan/$id'),
                      ),
                      const SizedBox(height: 14),
                    ],
                    const SectionTitle(title: 'Список кланов'),
                    if (list.isEmpty && top.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: EmptyStateCard(
                          title: 'Пока пусто',
                          subtitle: 'В этом рейтинге ещё нет кланов.',
                        ),
                      )
                    else
                      for (final e in list) ...[
                        _ClanRow(
                          entry: e,
                          onTap: () =>
                              context.push('/main/profile/rating/clan/${e.id}'),
                        ),
                        const SizedBox(height: 6),
                      ],
                    if (state.hasMore)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (state.myEntry != null)
              _StickyClanCard(
                entry: state.myEntry!,
                onTap: () =>
                    context.push('/main/profile/rating/clan/${state.myEntry!.id}'),
              ),
          ],
        );
      },
    );
  }
}

List<RankingPlayerEntry> _orderedTop3(List<RankingPlayerEntry> raw) {
  RankingPlayerEntry? at(int rank) {
    for (final e in raw) {
      if (e.rank == rank) return e;
    }
    return null;
  }

  return [at(2), at(1), at(3)].whereType<RankingPlayerEntry>().toList();
}

List<RankingClanEntry> _orderedTop3Clans(List<RankingClanEntry> raw) {
  RankingClanEntry? at(int rank) {
    for (final e in raw) {
      if (e.rank == rank) return e;
    }
    return null;
  }

  return [at(2), at(1), at(3)].whereType<RankingClanEntry>().toList();
}

Color _medalColor(int rank) {
  switch (rank) {
    case 1:
      return AppColors.gold;
    case 2:
      return AppColors.silver;
    case 3:
      return AppColors.bronze;
    default:
      return AppColors.textTertiary;
  }
}

class _PlayersPodium extends StatelessWidget {
  const _PlayersPodium({required this.entries, required this.onTap});

  final List<RankingPlayerEntry> entries;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _PodiumPlayerCard(
              entry: entries[i],
              featured: entries[i].rank == 1,
              onTap: () => onTap(entries[i].id),
            ),
          ),
        ],
      ],
    );
  }
}

class _ClansPodium extends StatelessWidget {
  const _ClansPodium({required this.entries, required this.onTap});

  final List<RankingClanEntry> entries;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _PodiumClanCard(
              entry: entries[i],
              featured: entries[i].rank == 1,
              onTap: () => onTap(entries[i].id),
            ),
          ),
        ],
      ],
    );
  }
}

class _PodiumPlayerCard extends StatelessWidget {
  const _PodiumPlayerCard({
    required this.entry,
    required this.featured,
    required this.onTap,
  });

  final RankingPlayerEntry entry;
  final bool featured;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final medal = _medalColor(entry.rank);
    final avatarSize = featured ? 56.0 : 44.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Container(
          padding: EdgeInsets.fromLTRB(8, featured ? 14 : 10, 8, 10),
          decoration: BoxDecoration(
            color: featured ? AppColors.cardSoft : AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(
              color: featured ? medal.withValues(alpha: 0.7) : AppColors.border,
              width: featured ? 1.4 : 1,
            ),
          ),
          child: Column(
            children: [
              _RankBadge(rank: entry.rank, color: medal),
              const SizedBox(height: 8),
              _Avatar(url: entry.avatarUrl, size: avatarSize, fallback: entry.nickname),
              const SizedBox(height: 8),
              Text(
                entry.nickname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: featured ? 13 : 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${entry.rating}',
                style: TextStyle(
                  fontSize: featured ? 15 : 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PodiumClanCard extends StatelessWidget {
  const _PodiumClanCard({
    required this.entry,
    required this.featured,
    required this.onTap,
  });

  final RankingClanEntry entry;
  final bool featured;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final medal = _medalColor(entry.rank);
    final size = featured ? 56.0 : 44.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Container(
          padding: EdgeInsets.fromLTRB(8, featured ? 14 : 10, 8, 10),
          decoration: BoxDecoration(
            color: featured ? AppColors.cardSoft : AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(
              color: featured ? medal.withValues(alpha: 0.7) : AppColors.border,
              width: featured ? 1.4 : 1,
            ),
          ),
          child: Column(
            children: [
              _RankBadge(rank: entry.rank, color: medal),
              const SizedBox(height: 8),
              _Emblem(url: entry.avatarUrl, tag: entry.tag, size: size),
              const SizedBox(height: 8),
              Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: featured ? 12.5 : 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                entry.displayTag,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${entry.rating}',
                style: TextStyle(
                  fontSize: featured ? 15 : 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank, required this.color});

  final int rank;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppRadii.badge),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.entry,
    required this.onTap,
    this.highlight = false,
  });

  final RankingPlayerEntry entry;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      accentBorder: highlight,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '${entry.rank}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          _Avatar(url: entry.avatarUrl, size: 36, fallback: entry.nickname),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.nickname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          Text(
            '${entry.rating}',
            style: const TextStyle(
              color: AppColors.accent,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClanRow extends StatelessWidget {
  const _ClanRow({required this.entry, required this.onTap});

  final RankingClanEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '${entry.rank}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          _Emblem(url: entry.avatarUrl, tag: entry.tag, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${entry.displayTag} · ${entry.membersCount} уч.',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${entry.rating}',
            style: const TextStyle(
              color: AppColors.accent,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _StickyPlayerCard extends StatelessWidget {
  const _StickyPlayerCard({
    required this.entry,
    required this.onTap,
    this.emphasize = true,
  });

  final RankingPlayerEntry entry;
  final VoidCallback onTap;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: AppCard(
        accentBorder: emphasize,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        onTap: onTap,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(AppRadii.badge),
                border: Border.all(color: AppColors.accentDim),
              ),
              child: Text(
                '#${entry.rank}',
                style: const TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 10),
            _Avatar(url: entry.avatarUrl, size: 34, fallback: entry.nickname),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Вы',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    entry.nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            Text(
              '${entry.rating}',
              style: const TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StickyClanCard extends StatelessWidget {
  const _StickyClanCard({required this.entry, required this.onTap});

  final RankingClanEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: AppCard(
        accentBorder: true,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        onTap: onTap,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(AppRadii.badge),
                border: Border.all(color: AppColors.accentDim),
              ),
              child: Text(
                '#${entry.rank}',
                style: const TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 10),
            _Emblem(url: entry.avatarUrl, tag: entry.tag, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ваш клан',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            Text(
              '${entry.rating}',
              style: const TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.url,
    required this.size,
    required this.fallback,
  });

  final String? url;
  final double size;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final letter = fallback.isNotEmpty ? fallback[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border),
        image: url != null && url!.isNotEmpty
            ? DecorationImage(image: NetworkImage(url!), fit: BoxFit.cover)
            : null,
      ),
      alignment: Alignment.center,
      child: url == null || url!.isEmpty
          ? Text(
              letter,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: size * 0.38,
                color: AppColors.accent,
              ),
            )
          : null,
    );
  }
}

class _Emblem extends StatelessWidget {
  const _Emblem({
    required this.url,
    required this.tag,
    required this.size,
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
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
        image: url != null && url!.isNotEmpty
            ? DecorationImage(image: NetworkImage(url!), fit: BoxFit.cover)
            : null,
      ),
      alignment: Alignment.center,
      child: url == null || url!.isEmpty
          ? Text(
              tag.length > 3 ? tag.substring(0, 3) : tag,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: size * 0.28,
                color: AppColors.accent,
              ),
            )
          : null,
    );
  }
}
