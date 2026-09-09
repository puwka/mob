import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../domain/models/polygon.dart';
import '../../../presentation/providers/polygon_providers.dart';
import '../../../services/map_launcher.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/feedback.dart';

class MyPolygonsScreen extends ConsumerWidget {
  const MyPolygonsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myPolygonsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Мои полигоны'),
        actions: [
          IconButton(
            tooltip: 'Добавить',
            onPressed: () =>
                context.push('/main/profile/organizer/polygons/create'),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            context.push('/main/profile/organizer/polygons/create'),
        backgroundColor: AppColors.accent,
        foregroundColor: const Color(0xFF121408),
        icon: const Icon(Icons.add),
        label: const Text('Полигон'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: AsyncErrorRetry(
            message: ErrorMapper.map(e),
            onRetry: () => ref.read(myPolygonsProvider.notifier).refresh(),
          ),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'Пока нет полигонов.\nСоздайте площадку и укажите точку на карте.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                ),
              ),
            );
          }

          return RefreshIndicator(
            color: AppColors.accent,
            onRefresh: () => ref.read(myPolygonsProvider.notifier).refresh(),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final p = list[i];
                return _PolygonTile(polygon: p);
              },
            ),
          );
        },
      ),
    );
  }
}

class _PolygonTile extends ConsumerWidget {
  const _PolygonTile({required this.polygon});

  final PolygonVenue polygon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      onTap: () => context.push(
        '/main/profile/organizer/polygons/${polygon.id}/edit',
        extra: polygon,
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
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
              Icons.map_outlined,
              color: AppColors.accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  polygon.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${polygon.city} · ${polygon.address}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'На карте',
            onPressed: () async {
              try {
                await MapLauncher.open(
                  latitude: polygon.latitude,
                  longitude: polygon.longitude,
                  query: '${polygon.city}, ${polygon.address}',
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ErrorMapper.map(e))),
                );
              }
            },
            icon: const Icon(Icons.open_in_new, size: 18),
          ),
        ],
      ),
    );
  }
}
