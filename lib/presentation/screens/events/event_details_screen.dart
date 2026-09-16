import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../core/utils/event_cover.dart';
import '../../../domain/models/event.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../presentation/providers/events_provider.dart';
import '../../../presentation/providers/progression_providers.dart';
import '../../../presentation/screens/map/place_map_screen.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_network_image.dart';
import '../../../widgets/event_side_pick_dialog.dart';
import '../../../widgets/feedback.dart';
import '../../../widgets/level_up_overlay.dart';
import '../../../widgets/photo_lightbox.dart';

class EventDetailsScreen extends ConsumerWidget {
  const EventDetailsScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(eventDetailsProvider(eventId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мероприятие'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: AsyncErrorRetry(
            message: ErrorMapper.map(e),
            onRetry: () =>
                ref.read(eventDetailsProvider(eventId).notifier).refresh(),
          ),
        ),
        data: (event) => _DetailsBody(event: event),
      ),
    );
  }
}

class _DetailsBody extends ConsumerStatefulWidget {
  const _DetailsBody({required this.event});

  final Event event;

  @override
  ConsumerState<_DetailsBody> createState() => _DetailsBodyState();
}

class _DetailsBodyState extends ConsumerState<_DetailsBody> {
  String? _actionError;
  bool _busy = false;
  int? _levelUpTo;
  var _photoIndex = 0;

  Event get event =>
      ref.watch(eventDetailsProvider(widget.event.id)).valueOrNull ??
      widget.event;

  void _consumeFeedback() {
    final feedback = ref.read(progressionFeedbackProvider);
    if (feedback == null || !feedback.hasContent) return;

    if (feedback.newLevel != null) {
      setState(() => _levelUpTo = feedback.newLevel);
    }

    for (final item in feedback.unlockedAchievements) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            item.achievement.rewardXp > 0
                ? 'Достижение: ${item.achievement.title} · +${item.achievement.rewardXp} XP'
                : 'Достижение: ${item.achievement.title}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    ref.read(progressionFeedbackProvider.notifier).state = null;
  }

  Future<void> _join() async {
    final side = await showEventSidePickDialog(
      context: context,
      event: event,
    );
    if (side == null || !mounted) return;

    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await ref
          .read(eventDetailsProvider(widget.event.id).notifier)
          .join(side);
      if (!mounted) return;
      _consumeFeedback();
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionError = ErrorMapper.map(e));
      await ref
          .read(eventDetailsProvider(widget.event.id).notifier)
          .refresh(silent: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await ref.read(eventDetailsProvider(widget.event.id).notifier).leave();
      if (!mounted) return;
      _consumeFeedback();
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionError = ErrorMapper.map(e));
      await ref
          .read(eventDetailsProvider(widget.event.id).notifier)
          .refresh(silent: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = event;
    final date = DateFormat('d MMMM yyyy', 'ru').format(e.eventDate.toLocal());
    final time = DateFormat('HH:mm', 'ru').format(e.eventDate.toLocal());
    final canJoin =
        !e.isParticipating && !e.isFull && !_busy && e.canRegister;
    final uid = ref.watch(authRepositoryProvider).currentUser?.id;
    final isManager = e.isManager(uid);

    return Stack(
      children: [
        RefreshIndicator(
          color: AppColors.accent,
          onRefresh: () =>
              ref.read(eventDetailsProvider(e.id).notifier).refresh(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            children: [
              Builder(
                builder: (context) {
                  final urls = e.galleryUrls;
                  final cover = urls.isEmpty
                      ? null
                      : urls[_photoIndex.clamp(0, urls.length - 1)];
                  return Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadii.card),
                        child: AspectRatio(
                          aspectRatio: EventCoverSpecs.aspectRatio,
                          child: cover == null
                              ? Container(
                                  color: AppColors.surfaceElevated,
                                  child: const Icon(
                                    Icons.image_outlined,
                                    color: AppColors.textTertiary,
                                  ),
                                )
                              : GestureDetector(
                                  onTap: () => showPhotoLightbox(
                                    context,
                                    urls: urls,
                                    initialIndex: _photoIndex,
                                  ),
                                  child: AppNetworkImage(
                                    url: cover,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 1200,
                                    debugLabel: 'event-detail',
                                  ),
                                ),
                        ),
                      ),
                      if (urls.length > 1) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 64,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: urls.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 6),
                            itemBuilder: (context, index) {
                              final selected = index == _photoIndex;
                              return GestureDetector(
                                onTap: () =>
                                    setState(() => _photoIndex = index),
                                child: Container(
                                  width: 64,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                      AppRadii.badge,
                                    ),
                                    border: Border.all(
                                      color: selected
                                          ? AppColors.accent
                                          : AppColors.border,
                                      width: selected ? 1.4 : 1,
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: AppNetworkImage(
                                    url: urls[index],
                                    fit: BoxFit.cover,
                                    width: 64,
                                    height: 64,
                                    memCacheWidth: 160,
                                    debugLabel: 'event-thumb',
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Text(
                e.title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: 20,
                    ),
              ),
              if (e.status == EventStatus.finished) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text(
                    'Завершено',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                e.description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 13.5,
                      height: 1.4,
                    ),
              ),
              if (e.hasRadioFrequency) ...[
                const SizedBox(height: 12),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.accentSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.cell_tower_outlined,
                          color: AppColors.accent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Частота рации',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              e.radioFrequency.trim(),
                              style: const TextStyle(
                                color: AppColors.accent,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (e.hasRules) ...[
                const SizedBox(height: 12),
                AppCard(
                  onTap: () => _openEventRules(context, e.rulesText),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.accentSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.gavel_outlined,
                          color: AppColors.accent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Правила',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Открыть правила мероприятия',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: AppColors.textTertiary,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              AppCard(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  children: [
                    _Meta(Icons.calendar_today_outlined, 'Дата', date),
                    const Divider(height: 18),
                    _Meta(Icons.schedule_outlined, 'Время', time),
                    const Divider(height: 18),
                    _Meta(Icons.location_city_outlined, 'Город', e.city),
                    const Divider(height: 18),
                    _Meta(
                      Icons.place_outlined,
                      'Адрес',
                      e.location,
                      onTap: () => _openEventMap(context, e),
                      trailing: Icons.map_outlined,
                    ),
                    const Divider(height: 18),
                    _Meta(
                      Icons.person_outline,
                      'Организатор',
                      e.organizerNickname ?? 'Не указан',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              AppCard(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle(title: 'Участники'),
                    Row(
                      children: [
                        Text(
                          '${e.participantsCount} / ${e.maxParticipants}',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontSize: 22,
                                color: e.isFull
                                    ? AppColors.warning
                                    : AppColors.accent,
                              ),
                        ),
                        const Spacer(),
                        Text(
                          e.isFull
                              ? 'Набор закрыт'
                              : 'Свободно: ${e.slotsLeft}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: e.fillProgress,
                        minHeight: 5,
                        backgroundColor: AppColors.border,
                        color:
                            e.isFull ? AppColors.warning : AppColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
              if (_actionError != null) ...[
                const SizedBox(height: 10),
                ErrorBanner(message: _actionError!),
              ],
              const SizedBox(height: 14),
              if (e.isParticipating) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: e.mySide == EventSide.dark
                        ? AppColors.dangerMuted
                        : AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(AppRadii.button),
                    border: Border.all(
                      color: (e.mySide == EventSide.dark
                              ? AppColors.danger
                              : AppColors.accent)
                          .withValues(alpha: 0.45),
                    ),
                  ),
                  child: Text(
                    e.mySide == null
                        ? 'Вы участвуете'
                        : 'Вы участвуете · ${e.mySide!.labelRu}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: e.mySide == EventSide.dark
                              ? AppColors.danger
                              : AppColors.accent,
                          fontSize: 13.5,
                        ),
                  ),
                ),
                const SizedBox(height: 8),
                AppButton(
                  label: 'Отменить участие',
                  loading: _busy,
                  onPressed: _busy ? null : _leave,
                  variant: AppButtonVariant.secondary,
                ),
              ] else
                AppButton(
                  label: e.isFull
                      ? 'Мест нет'
                      : e.status == EventStatus.finished
                          ? 'Завершено'
                          : 'Участвовать',
                  loading: _busy,
                  onPressed: canJoin ? _join : null,
                ),
              if (isManager) ...[
                const SizedBox(height: 8),
                AppButton(
                  label: 'Управление',
                  variant: AppButtonVariant.secondary,
                  icon: Icons.settings_outlined,
                  onPressed: () => context.push(
                    '/main/profile/organizer/events/${e.id}',
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_levelUpTo != null)
          LevelUpOverlay(
            level: _levelUpTo!,
            onFinished: () => setState(() => _levelUpTo = null),
          ),
      ],
    );
  }
}

void _openEventRules(BuildContext context, String rulesText) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    builder: (context) {
      final height = MediaQuery.sizeOf(context).height * 0.72;
      return SafeArea(
        child: SizedBox(
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Правила',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Закрыть',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Text(
                    rulesText.trim(),
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.45,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _Meta extends StatelessWidget {
  const _Meta(
    this.icon,
    this.label,
    this.value, {
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textTertiary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                    ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontSize: 14,
                      color: onTap == null ? null : AppColors.accent,
                      decoration:
                          onTap == null ? null : TextDecoration.underline,
                      decorationColor: AppColors.accent,
                    ),
              ),
            ],
          ),
        ),
        if (trailing != null)
          Icon(trailing, size: 18, color: AppColors.accent),
      ],
    );

    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: row,
    );
  }
}

Future<void> _openEventMap(BuildContext context, Event event) async {
  try {
    await openPlaceMapInApp(
      context,
      latitude: event.latitude,
      longitude: event.longitude,
      query: '${event.city}, ${event.location}',
      title: 'Место проведения',
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ErrorMapper.map(e))),
    );
  }
}
