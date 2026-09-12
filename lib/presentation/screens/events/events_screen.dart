import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/event_cities.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../domain/models/event.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../presentation/providers/events_provider.dart';
import '../../../widgets/app_network_image.dart';
import '../../../widgets/app_page_body.dart';
import '../../../widgets/city_picker.dart';
import '../../../widgets/event_list_skeleton.dart';
import '../../../widgets/feedback.dart';
import '../../../services/app_image_cache.dart';

class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  Future<void> _pickCity(BuildContext context, WidgetRef ref) async {
    final filter = ref.read(eventCityFilterProvider);
    final profileCity =
        ref.read(currentProfileProvider).valueOrNull?.city.trim();
    final selected = await showCityPicker(
      context,
      selected: filter == EventCities.all ? profileCity : filter,
      priorityCity: profileCity,
    );
    if (selected == null) return;
    ref.read(eventCityFilterProvider.notifier).state = selected;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(eventCityFilterProvider);
    final eventsAsync = ref.watch(eventsListProvider);
    final gutter = AppLayout.pageGutter(context);
    final citySelected = filter != EventCities.all;

    return Scaffold(
      appBar: AppBar(title: const Text('Мероприятия')),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: Row(
              children: [
                _FilterChip(
                  label: EventCities.all,
                  selected: !citySelected,
                  onTap: () {
                    ref.read(eventCityFilterProvider.notifier).state =
                        EventCities.all;
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Material(
                    color: citySelected
                        ? AppColors.accentSoft
                        : AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(AppRadii.chip),
                    child: InkWell(
                      onTap: () => _pickCity(context, ref),
                      borderRadius: BorderRadius.circular(AppRadii.chip),
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadii.chip),
                          border: Border.all(
                            color: citySelected
                                ? AppColors.accentDim
                                : AppColors.border,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.location_city_outlined,
                              size: 16,
                              color: citySelected
                                  ? AppColors.accent
                                  : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                citySelected ? filter : 'Выбрать город',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: citySelected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: citySelected
                                      ? AppColors.textPrimary
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.expand_more,
                              size: 18,
                              color: citySelected
                                  ? AppColors.accent
                                  : AppColors.textTertiary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: AppPageBody(
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
                        padding: EdgeInsets.all(gutter),
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
                    child: Builder(
                      builder: (context) {
                        AppImageCache.prefetch(
                          events.take(16).map((e) => e.imageUrl),
                          limit: 16,
                        );
                        return ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: AppLayout.pagePadding(context),
                          itemCount: events.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final event = events[index];
                            return EventRowCard(
                              event: event,
                              onTap: () =>
                                  context.push('/main/games/${event.id}'),
                            );
                          },
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadii.chip),
          border: Border.all(
            color: selected ? AppColors.accentDim : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color:
                selected ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
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
    final h = AppLayout.eventListThumb(context);
    final thumbW = h;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Container(
          constraints: BoxConstraints(minHeight: h),
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
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: thumbW,
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
                      : ColoredBox(
                          color: AppColors.surfaceElevated,
                          child: AppNetworkImage(
                            url: event.imageUrl,
                            fit: BoxFit.cover,
                            // Only one mem-cache axis — both stretch the decode.
                            memCacheWidth: (thumbW * MediaQuery.devicePixelRatioOf(context) * 1.5)
                                .round()
                                .clamp(64, 512),
                            debugLabel: 'event-cover',
                          ),
                        ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${event.city} · $date · $time',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontSize: 12,
                                  ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          event.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
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
      ),
    );
  }
}
