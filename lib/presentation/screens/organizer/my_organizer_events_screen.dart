import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../domain/models/event.dart';
import '../../../presentation/providers/organizer_events_providers.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/feedback.dart';

class MyOrganizerEventsScreen extends ConsumerWidget {
  const MyOrganizerEventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myOrganizerEventsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Мои мероприятия'),
        actions: [
          IconButton(
            tooltip: 'Создать',
            onPressed: () =>
                context.push('/main/profile/organizer/events/create'),
            icon: const Icon(Icons.add, size: 20),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: AsyncErrorRetry(
            message: ErrorMapper.map(e),
            onRetry: () =>
                ref.read(myOrganizerEventsProvider.notifier).refresh(),
          ),
        ),
        data: (events) {
          if (events.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SizedBox(height: 40),
                EmptyStateCard(
                  title: 'Пока пусто',
                  subtitle: 'Создайте первое мероприятие',
                  icon: Icons.event_note_outlined,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () =>
                      context.push('/main/profile/organizer/events/create'),
                  child: const Text('Создать мероприятие'),
                ),
              ],
            );
          }

          return RefreshIndicator(
            color: AppColors.accent,
            onRefresh: () =>
                ref.read(myOrganizerEventsProvider.notifier).refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: events.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final e = events[index];
                return _EventTile(
                  event: e,
                  onTap: () => context.push(
                    '/main/profile/organizer/events/${e.id}',
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.onTap});

  final Event event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('d MMMM', 'ru').format(event.eventDate.toLocal());

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadii.badge),
                  border: Border.all(color: AppColors.accentDim),
                ),
                child: Text(
                  event.status.labelRu,
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${event.city} · $date',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${event.participantsCount} участников / ${event.maxParticipants}',
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
