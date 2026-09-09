import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../domain/models/listing.dart';
import '../../../presentation/providers/market_providers.dart';
import '../../../widgets/feedback.dart';
import '../../../widgets/listing_card.dart';

class MyListingsScreen extends ConsumerWidget {
  const MyListingsScreen({super.key});

  static const _tabs = <ListingStatus?>[
    ListingStatus.active,
    ListingStatus.pending,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(myListingsStatusFilterProvider);
    final async = ref.watch(myListingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои объявления'),
        actions: [
          IconButton(
            tooltip: 'Создать',
            onPressed: () => context.push('/main/market/create'),
            icon: const Icon(Icons.add, size: 20),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _tabs.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final tab = _tabs[index]!;
                final selected = status == tab;
                return GestureDetector(
                  onTap: () => ref
                      .read(myListingsStatusFilterProvider.notifier)
                      .state = tab,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.accentSoft
                          : AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(AppRadii.chip),
                      border: Border.all(
                        color:
                            selected ? AppColors.accentDim : AppColors.border,
                      ),
                    ),
                    child: Text(
                      tab.labelRu,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => AsyncErrorRetry(
                message: ErrorMapper.map(e),
                onRetry: () =>
                    ref.read(myListingsProvider.notifier).refresh(),
              ),
              data: (listings) {
                if (listings.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: EmptyStateCard(
                      title: 'Пока пусто',
                      subtitle: 'Здесь появятся ваши объявления.',
                      icon: Icons.inventory_2_outlined,
                    ),
                  );
                }
                return RefreshIndicator(
                  color: AppColors.accent,
                  onRefresh: () =>
                      ref.read(myListingsProvider.notifier).refresh(),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    itemCount: listings.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = listings[index];
                      return Column(
                        children: [
                          ListingCard(
                            listing: item,
                            onTap: () =>
                                context.push('/main/market/${item.id}'),
                          ),
                          const SizedBox(height: 6),
                          _ActionsRow(
                            listing: item,
                            onEdit: () =>
                                context.push('/main/market/${item.id}/edit'),
                            onDelete: () =>
                                _confirmDelete(context, ref, item.id),
                          ),
                        ],
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Удалить объявление?'),
        content: const Text('Действие необратимо.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(myListingsProvider.notifier).delete(id);
    }
  }
}

class _ActionsRow extends StatelessWidget {
  const _ActionsRow({
    required this.listing,
    required this.onEdit,
    required this.onDelete,
  });

  final Listing listing;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      children: [
        if (listing.status == ListingStatus.active ||
            listing.status == ListingStatus.pending)
          _Action(label: 'Изменить', onTap: onEdit),
        _Action(label: 'Удалить', onTap: onDelete, danger: true),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        foregroundColor: danger ? AppColors.danger : AppColors.accent,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12.5)),
    );
  }
}
