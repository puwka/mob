import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../domain/models/event.dart';
import '../../../presentation/providers/events_provider.dart';
import '../../../presentation/providers/progression_providers.dart';
import '../../../services/map_launcher.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/feedback.dart';
import '../../../widgets/level_up_overlay.dart';

class EventDetailsScreen extends ConsumerWidget {
  const EventDetailsScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(eventDetailsProvider(eventId));

    return Scaffold(
      appBar: AppBar(title: const Text('Мероприятие')),
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
          content: Text('Достижение: ${item.achievement.title}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    ref.read(progressionFeedbackProvider.notifier).state = null;
  }

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await ref.read(eventDetailsProvider(widget.event.id).notifier).join();
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
    final canJoin = !e.isParticipating && !e.isFull && !_busy;

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
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.card),
                child: AspectRatio(
                  aspectRatio: 16 / 8.5,
                  child: e.imageUrl == null || e.imageUrl!.isEmpty
                      ? Container(
                          color: AppColors.surfaceElevated,
                          child: const Icon(
                            Icons.image_outlined,
                            color: AppColors.textTertiary,
                          ),
                        )
                      : Image.network(
                          e.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                            color: AppColors.surfaceElevated,
                            child: const Icon(
                              Icons.broken_image_outlined,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                e.title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: 20,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                e.description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 13.5,
                      height: 1.4,
                    ),
              ),
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
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(AppRadii.button),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Text(
                    'Вы участвуете',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AppColors.accent,
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
                  label: e.isFull ? 'Мест нет' : 'Участвовать',
                  loading: _busy,
                  onPressed: canJoin ? _join : null,
                ),
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
    await MapLauncher.open(
      latitude: event.latitude,
      longitude: event.longitude,
      query: '${event.city}, ${event.location}',
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ErrorMapper.map(e))),
    );
  }
}
