import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../domain/models/conversation.dart';
import '../../../domain/models/event.dart';
import '../../../presentation/providers/chat_providers.dart';
import '../../../presentation/providers/events_provider.dart';
import '../../../presentation/providers/organizer_events_providers.dart';
import '../../../presentation/providers/repository_providers.dart';
import '../../../services/map_launcher.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/feedback.dart';

class OrganizerEventDetailsScreen extends ConsumerStatefulWidget {
  const OrganizerEventDetailsScreen({super.key, required this.eventId});

  final String eventId;

  @override
  ConsumerState<OrganizerEventDetailsScreen> createState() =>
      _OrganizerEventDetailsScreenState();
}

class _OrganizerEventDetailsScreenState
    extends ConsumerState<OrganizerEventDetailsScreen> {
  var _deleting = false;
  var _finishing = false;

  Future<void> _finishEvent(Event event) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Завершить мероприятие?'),
        content: Text(
          '«${event.title}» будет отмечено как завершённое. '
          'Чат мероприятия удалится у всех участников.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Завершить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _finishing = true);
    try {
      await ref.read(eventRepositoryProvider).finishEvent(widget.eventId);
      ref.invalidate(eventDetailsProvider(widget.eventId));
      ref.invalidate(myOrganizerEventsProvider);
      ref.invalidate(conversationsByTypeProvider(ConversationType.event));
      ref.invalidate(eventsListProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Мероприятие завершено')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorMapper.map(e))),
      );
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  Future<void> _deleteEvent(Event event) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Удалить мероприятие?'),
        content: Text(
          '«${event.title}» будет удалено вместе с записями участников. '
          'Это действие нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Удалить',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await ref.read(eventRepositoryProvider).deleteEvent(widget.eventId);
      ref.invalidate(myOrganizerEventsProvider);
      ref.invalidate(eventDetailsProvider(widget.eventId));
      ref.invalidate(eventsListProvider);
      ref.invalidate(conversationsByTypeProvider(ConversationType.event));
      if (!mounted) return;
      context.go('/main/profile/organizer/events');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Мероприятие удалено')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorMapper.map(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(eventDetailsProvider(widget.eventId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Мероприятие'),
        actions: [
          if (async.hasValue)
            IconButton(
              tooltip: 'Удалить',
              onPressed: _deleting ? null : () => _deleteEvent(async.requireValue),
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: AsyncErrorRetry(
            message: ErrorMapper.map(e),
            onRetry: () => ref
                .read(eventDetailsProvider(widget.eventId).notifier)
                .refresh(),
          ),
        ),
        data: (event) {
          final date = DateFormat('d MMMM yyyy, HH:mm', 'ru')
              .format(event.eventDate.toLocal());
          final eventId = widget.eventId;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (event.imageUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(event.imageUrl!, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                event.title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _Chip(event.status.labelRu),
                  _Chip(event.city),
                  _Chip(date),
                ],
              ),
              const SizedBox(height: 12),
              AppCard(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle(title: 'Участники'),
                    Text(
                      '${event.participantsCount} / ${event.maxParticipants}',
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () async {
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
                      },
                      child: Row(
                        children: [
                          const Icon(
                            Icons.place_outlined,
                            size: 16,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              event.location,
                              style: const TextStyle(
                                color: AppColors.accent,
                                fontSize: 13,
                                decoration: TextDecoration.underline,
                                decorationColor: AppColors.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (event.description.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionTitle(title: 'Описание'),
                      Text(
                        event.description,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.4,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              AppButton(
                label: 'Участники',
                variant: AppButtonVariant.secondary,
                onPressed: _deleting
                    ? null
                    : () => context.push(
                          '/main/profile/organizer/events/$eventId/participants',
                        ),
              ),
              const SizedBox(height: 8),
              AppButton(
                label: 'Сканировать QR',
                icon: Icons.qr_code_scanner,
                onPressed: !_deleting &&
                        !_finishing &&
                        event.status == EventStatus.active
                    ? () => context.push(
                          '/main/profile/organizer/events/$eventId/scanner',
                        )
                    : null,
              ),
              if (event.status == EventStatus.active ||
                  event.status == EventStatus.draft) ...[
                const SizedBox(height: 8),
                AppButton(
                  label: 'Завершить мероприятие',
                  icon: Icons.flag_outlined,
                  loading: _finishing,
                  onPressed: _deleting || _finishing
                      ? null
                      : () => _finishEvent(event),
                ),
              ],
              const SizedBox(height: 8),
              AppButton(
                label: 'Удалить мероприятие',
                variant: AppButtonVariant.danger,
                loading: _deleting,
                icon: Icons.delete_outline,
                onPressed: _deleting || _finishing
                    ? null
                    : () => _deleteEvent(event),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadii.badge),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
      ),
    );
  }
}

class EventParticipantsScreen extends ConsumerWidget {
  const EventParticipantsScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(eventParticipantsProvider(eventId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Участники')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: AsyncErrorRetry(
            message: ErrorMapper.map(e),
            onRetry: () => ref.invalidate(eventParticipantsProvider(eventId)),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: EmptyStateCard(
                title: 'Нет участников',
                subtitle: 'Пока никто не зарегистрировался',
              ),
            );
          }

          return RefreshIndicator(
            color: AppColors.accent,
            onRefresh: () async {
              ref.invalidate(eventParticipantsProvider(eventId));
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final p = items[index];
                return AppCard(
                  padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                  child: Row(
                    children: [
                      _Avatar(url: p.avatarUrl, name: p.nickname ?? '?'),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.nickname ?? 'Боец',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              p.city ?? '',
                              style: const TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _AttendanceBadge(confirmed: p.isConfirmed),
                    ],
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

class _AttendanceBadge extends StatelessWidget {
  const _AttendanceBadge({required this.confirmed});

  final bool confirmed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: confirmed ? AppColors.accentSoft : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadii.badge),
        border: Border.all(
          color: confirmed ? AppColors.accentDim : AppColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            confirmed ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 13,
            color: confirmed ? AppColors.accent : AppColors.textTertiary,
          ),
          const SizedBox(width: 4),
          Text(
            confirmed ? 'Присутствует' : 'Не подтвержден',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: confirmed ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.name});

  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) {
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceElevated,
        border: Border.all(color: AppColors.border),
        image: url != null
            ? DecorationImage(image: NetworkImage(url!), fit: BoxFit.cover)
            : null,
      ),
      alignment: Alignment.center,
      child: url == null
          ? Text(
              letter,
              style: const TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w800,
              ),
            )
          : null,
    );
  }
}
