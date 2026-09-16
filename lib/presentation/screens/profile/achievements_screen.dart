import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/app_layout.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../domain/models/user_achievement_progress.dart';
import '../../../presentation/providers/profile_providers.dart';
import '../../../presentation/providers/repository_providers.dart';
import '../../../services/achievement_service.dart';
import '../../../widgets/achievement_card.dart';
import '../../../widgets/feedback.dart';

class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final achievements = ref.watch(achievementsProvider);
    final service = ref.watch(achievementServiceProvider);
    final gutter = AppLayout.pageGutter(context);
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: achievements.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: AsyncErrorRetry(
            message: ErrorMapper.map(e),
            onRetry: () => ref.read(achievementsProvider.notifier).refresh(),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return CustomScrollView(
              slivers: [
                _HeroHeader(topInset: topInset),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.all(gutter),
                    child: const EmptyStateCard(
                      title: 'Пока нет достижений',
                      subtitle:
                          'Каталог появится после синхронизации с сервером.',
                      icon: Icons.military_tech_outlined,
                    ),
                  ),
                ),
              ],
            );
          }

          final unlocked = items.where((e) => e.unlocked).length;

          return RefreshIndicator(
            color: AppColors.accent,
            onRefresh: () =>
                ref.read(achievementsProvider.notifier).refresh(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                _HeroHeader(topInset: topInset),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 14),
                    child: _SummaryCard(
                      unlocked: unlocked,
                      total: items.length,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 28),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.72,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = items[index];
                        final state = service.visualState(item);
                        return AchievementCatalogCard(
                          item: item,
                          state: state,
                          onTap: () => _openDetails(context, item, state),
                        );
                      },
                      childCount: items.length,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openDetails(
    BuildContext context,
    UserAchievementProgress item,
    AchievementVisualState state,
  ) {
    final unlocked = state == AchievementVisualState.unlocked;
    final required = item.achievement.requiredValue;
    final progress = unlocked ? required : item.progress;
    final ratio =
        required == 0 ? 1.0 : (progress / required).clamp(0.0, 1.0);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 16),
                AchievementHexBadge(
                  size: 72,
                  fill: unlocked
                      ? const Color(0xFF2A2410)
                      : const Color(0xFF1E2228),
                  stroke: unlocked ? AppColors.gold : AppColors.silver,
                  strokeWidth: 1.8,
                  child: AchievementGlyph(
                    icon: item.achievement.icon,
                    size: 32,
                    color: unlocked ? AppColors.gold : AppColors.silver,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  item.achievement.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.achievement.description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '$progress / $required',
                  style: TextStyle(
                    color: unlocked ? AppColors.gold : AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: ratio.toDouble(),
                    minHeight: 6,
                    backgroundColor: AppColors.surfaceElevated,
                    color: unlocked ? AppColors.gold : AppColors.silver,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.topInset});

  final double topInset;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 168 + topInset,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF1A1C20),
                    Color(0xFF0F1114),
                    AppColors.background,
                  ],
                ),
              ),
            ),
            Positioned(
              right: -20,
              top: topInset + 10,
              child: Icon(
                Icons.military_tech_outlined,
                size: 140,
                color: AppColors.gold.withValues(alpha: 0.07),
              ),
            ),
            Positioned(
              left: -30,
              bottom: 20,
              child: Icon(
                Icons.shield_outlined,
                size: 110,
                color: AppColors.silver.withValues(alpha: 0.05),
              ),
            ),
            Positioned(
              left: 4,
              top: topInset + 2,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                color: AppColors.textPrimary,
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ДОСТИЖЕНИЯ',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                          fontSize: 26,
                        ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'ВЫПОЛНЯЙ ЗАДАЧИ — ПОЛУЧАЙ ПРИЗНАНИЕ',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.unlocked,
    required this.total,
  });

  final int unlocked;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : unlocked / total;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          AchievementHexBadge(
            size: 48,
            fill: const Color(0xFF2A2410),
            stroke: AppColors.gold,
            strokeWidth: 1.6,
            child: const Icon(
              Icons.military_tech,
              color: AppColors.gold,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ВСЕГО ДОСТИЖЕНИЙ',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$unlocked / $total',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 88,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 7,
                backgroundColor: AppColors.surfaceElevated,
                color: AppColors.silver,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
