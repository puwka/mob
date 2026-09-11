import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/app_layout.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../presentation/providers/profile_providers.dart';
import '../../../presentation/providers/repository_providers.dart';
import '../../../widgets/achievement_card.dart';
import '../../../widgets/app_page_body.dart';
import '../../../widgets/feedback.dart';

class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final achievements = ref.watch(achievementsProvider);
    final service = ref.watch(achievementServiceProvider);
    final columns = AppLayout.gridCount(context, minTile: 108);
    final gutter = AppLayout.pageGutter(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Достижения')),
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
            return Padding(
              padding: EdgeInsets.all(gutter),
              child: const EmptyStateCard(
                title: 'Пока нет достижений',
                subtitle: 'Каталог появится после синхронизации с сервером.',
                icon: Icons.military_tech_outlined,
              ),
            );
          }

          return AppPageBody(
            child: RefreshIndicator(
              color: AppColors.accent,
              onRefresh: () =>
                  ref.read(achievementsProvider.notifier).refresh(),
              child: GridView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 24),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 10,
                  childAspectRatio: columns >= 4 ? 0.85 : 0.78,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return AchievementCard(
                    item: item,
                    state: service.visualState(item),
                    compact: true,
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
