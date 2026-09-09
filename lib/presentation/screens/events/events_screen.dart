import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/event_cities.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../core/utils/event_cover.dart';
import '../../../domain/models/event.dart';
import '../../../presentation/providers/events_provider.dart';
import '../../../presentation/providers/repository_providers.dart';
import '../../../widgets/app_network_image.dart';
import '../../../widgets/event_list_skeleton.dart';
import '../../../widgets/feedback.dart';

final eventFilterCitiesProvider = FutureProvider<List<String>>((ref) async {
  final names =
      await ref.watch(citiesRepositoryProvider).fetchActiveNames();
  return EventCities.filterOptionsFrom(names);
});

class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(eventCityFilterProvider);
    final eventsAsync = ref.watch(eventsListProvider);
    final cities =
        ref.watch(eventFilterCitiesProvider).valueOrNull ??
            EventCities.filterOptions;

    return Scaffold(
      appBar: AppBar(title: const Text('Мероприятия')),
      body: Column(
        children: [
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: cities.length,
              separatorBuilder: (context, index) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final city = cities[index];
                final selected = city == filter;
                return GestureDetector(
                  onTap: () {
                    ref.read(eventCityFilterProvider.notifier).state = city;
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.accentSoft
                          : AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(AppRadii.chip),
                      border: Border.all(
                        color: selected ? AppColors.accentDim : AppColors.border,
                      ),
                    ),
                    child: Text(
                      city,
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
            child: eventsAsync.when(
              loading: () => const EventListSkeleton(),
              error: (e, _) => AsyncErrorRetry(
                message: ErrorMapper.map(e),
                onRetry: () =>
                    ref.read(eventsListProvider.notifier).refresh(),
              ),
              data: (events) {
                if (events.isEmpty) {
                  return RefreshIndicator(
                    color: AppColors.accent,
                    onRefresh: () =>
                        ref.read(eventsListProvider.notifier).refresh(),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: const [
                        SizedBox(height: 60),
                        EmptyStateCard(
                          title: 'Мероприятий не найдено',
                          subtitle:
                              'Попробуйте другой город или обновите список.',
                          icon: Icons.event_busy_outlined,
                        ),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  color: AppColors.accent,
                  onRefresh: () =>
                      ref.read(eventsListProvider.notifier).refresh(),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    itemCount: events.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final event = events[index];
                      return EventRowCard(
                        event: event,
                        onTap: () => context.push('/main/games/${event.id}'),
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
}

/// Compact event row: fixed-size thumb + info (all cards same height).
class EventRowCard extends StatelessWidget {
  const EventRowCard({
    super.key,
    required this.event,
    required this.onTap,
  });

  final Event event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('d MMM', 'ru').format(event.eventDate.toLocal());
    final time = DateFormat('HH:mm', 'ru').format(event.eventDate.toLocal());
    const h = EventCoverSpecs.listCardHeight;
    const thumbW = EventCoverSpecs.listThumbWidth;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Container(
          height: h,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(
              color: event.isParticipating
                  ? AppColors.accent.withValues(alpha: 0.5)
                  : AppColors.border,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              SizedBox(
                width: thumbW,
                height: h,
                child: event.imageUrl == null || event.imageUrl!.isEmpty
                    ? const ColoredBox(
                        color: AppColors.surfaceElevated,
                        child: Center(
                          child: Icon(
                            Icons.image_outlined,
                            color: AppColors.textTertiary,
                            size: 26,
                          ),
                        ),
                      )
                      : AppNetworkImage(
                          url: event.imageUrl,
                          width: thumbW,
                          height: h,
                          fit: BoxFit.cover,
                          memCacheWidth: 280,
                          memCacheHeight: 280,
                          debugLabel: 'event-cover',
                        ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${event.city} · $date · $time',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: 12,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        event.location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: 12,
                            ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Text(
                            '${event.participantsCount}/${event.maxParticipants}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: AppColors.accent,
                                  fontSize: 13.5,
                                ),
                          ),
                          const Spacer(),
                          if (event.isParticipating)
                            Text(
                              'Вы в составе',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: AppColors.accent,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                            )
                          else
                            Text(
                              event.isFull ? 'Мест нет' : 'Открыто',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: event.isFull
                                        ? AppColors.warning
                                        : AppColors.textSecondary,
                                    fontSize: 11.5,
                                  ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
