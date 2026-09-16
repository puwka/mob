import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../domain/models/conversation.dart';
import '../../../domain/models/event.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../presentation/providers/chat_providers.dart';
import '../../../presentation/providers/events_provider.dart';
import '../../../presentation/providers/organizer_events_providers.dart';
import '../../../presentation/providers/repository_providers.dart';
import '../../../presentation/screens/map/place_map_screen.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_network_image.dart';
import '../../../widgets/feedback.dart';
import '../../../widgets/photo_lightbox.dart';

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
          'Чат останется ещё 3 дня: писать смогут только организатор и помощник. '
          'После завершения можно заполнить отчёт об итогах.',
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
      final fillReport = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Мероприятие завершено'),
          content: const Text(
            'Заполнить отчёт — кто победил и с каким счётом? '
            'Итоги появятся в чате мероприятия.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Позже'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Заполнить'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (fillReport == true) {
        context.push(
          '/main/profile/organizer/events/${widget.eventId}/report',
        );
      }
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
    final uid = ref.watch(authRepositoryProvider).currentUser?.id;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Мероприятие'),
        actions: [
          if (async.hasValue) ...[
            IconButton(
              tooltip: 'Изменить',
              onPressed: _deleting || _finishing
                  ? null
                  : () => context.push(
                        '/main/profile/organizer/events/${widget.eventId}/edit',
                      ),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Удалить',
              onPressed:
                  _deleting ? null : () => _deleteEvent(async.requireValue),
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
            ),
          ],
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
              if (event.galleryUrls.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: GestureDetector(
                      onTap: () => showPhotoLightbox(
                        context,
                        urls: event.galleryUrls,
                      ),
                      child: AppNetworkImage(
                        url: event.galleryUrls.first,
                        fit: BoxFit.cover,
                        memCacheWidth: 900,
                        debugLabel: 'org-event',
                      ),
                    ),
                  ),
                ),
                if (event.galleryUrls.length > 1) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 56,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: event.galleryUrls.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (context, index) {
                        return GestureDetector(
                          onTap: () => showPhotoLightbox(
                            context,
                            urls: event.galleryUrls,
                            initialIndex: index,
                          ),
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(AppRadii.badge),
                            child: AppNetworkImage(
                              url: event.galleryUrls[index],
                              fit: BoxFit.cover,
                              width: 56,
                              height: 56,
                              memCacheWidth: 140,
                              debugLabel: 'org-event-thumb',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
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
                label: 'Изменить',
                icon: Icons.edit_outlined,
                variant: AppButtonVariant.secondary,
                onPressed: _deleting || _finishing
                    ? null
                    : () => context.push(
                          '/main/profile/organizer/events/$eventId/edit',
                        ),
              ),
              const SizedBox(height: 8),
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
              if (event.needsReport) ...[
                const SizedBox(height: 8),
                AppButton(
                  label: 'Заполнить отчёт',
                  icon: Icons.emoji_events_outlined,
                  onPressed: _deleting || _finishing
                      ? null
                      : () => context.push(
                            '/main/profile/organizer/events/$eventId/report',
                          ),
                ),
              ],
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
              if (event.isOrganizerOwner(uid)) ...[
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

  Future<void> _assign(
    BuildContext context,
    WidgetRef ref,
    EventParticipant p,
    Event event,
  ) async {
    final uid = ref.read(authRepositoryProvider).currentUser?.id;
    if (!event.isOrganizerOwner(uid)) return;

    final isCurrent = event.assistantUserId == p.userId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(isCurrent ? 'Снять помощника?' : 'Назначить помощником?'),
        content: Text(
          isCurrent
              ? 'У ${p.nickname ?? 'бойца'} больше не будет прав помощника организатора.'
              : '${p.nickname ?? 'Боец'} получит права помощника: сканирование, редактирование и завершение. '
                  'Создавать и удалять мероприятия сможет только организатор.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(isCurrent ? 'Снять' : 'Назначить'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      if (isCurrent) {
        await ref.read(eventRepositoryProvider).clearEventAssistant(eventId);
      } else {
        await ref.read(eventRepositoryProvider).setEventAssistant(
              eventId: eventId,
              userId: p.userId,
            );
      }
      ref.invalidate(eventDetailsProvider(eventId));
      ref.invalidate(eventParticipantsProvider(eventId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isCurrent ? 'Помощник снят' : 'Помощник назначен',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorMapper.map(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(eventParticipantsProvider(eventId));
    final event = ref.watch(eventDetailsProvider(eventId)).valueOrNull;
    final max = event?.maxParticipants ?? 0;
    final uid = ref.watch(authRepositoryProvider).currentUser?.id;
    final canAssign = event?.isOrganizerOwner(uid) == true;

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

          final light = [
            for (final p in items)
              if (p.side == EventSide.light) p,
          ];
          final dark = [
            for (final p in items)
              if (p.side == EventSide.dark) p,
          ];
          final unset = [
            for (final p in items)
              if (p.side == null) p,
          ];

          Widget tile(EventParticipant p, Color accent) {
            final isAssistant = event?.assistantUserId == p.userId;
            return _ParticipantTile(
              participant: p,
              accent: accent,
              isAssistant: isAssistant,
              onAssignTap: canAssign && event != null
                  ? () => _assign(context, ref, p, event)
                  : null,
            );
          }

          return RefreshIndicator(
            color: AppColors.accent,
            onRefresh: () async {
              ref.invalidate(eventParticipantsProvider(eventId));
              ref.invalidate(eventDetailsProvider(eventId));
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (canAssign)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Нажмите на участника, чтобы назначить помощником организатора.',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                if (event?.assistantNickname != null) ...[
                  AppCard(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.support_agent,
                          color: AppColors.accent,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Помощник: ${event!.assistantNickname}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _TeamSection(
                  side: EventSide.light,
                  participants: light,
                  maxParticipants: max,
                  tileBuilder: tile,
                ),
                const SizedBox(height: 14),
                _TeamSection(
                  side: EventSide.dark,
                  participants: dark,
                  maxParticipants: max,
                  tileBuilder: tile,
                ),
                if (unset.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Без стороны',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final p in unset) ...[
                    tile(p, AppColors.textTertiary),
                    const SizedBox(height: 6),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TeamSection extends StatelessWidget {
  const _TeamSection({
    required this.side,
    required this.participants,
    required this.maxParticipants,
    required this.tileBuilder,
  });

  final EventSide side;
  final List<EventParticipant> participants;
  final int maxParticipants;
  final Widget Function(EventParticipant p, Color accent) tileBuilder;

  @override
  Widget build(BuildContext context) {
    final isLight = side == EventSide.light;
    final color = isLight ? AppColors.accent : AppColors.danger;
    final soft = isLight ? AppColors.accentSoft : AppColors.dangerMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.card),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                soft,
                AppColors.card,
                soft.withValues(alpha: 0.35),
              ],
            ),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Icon(
                isLight ? Icons.wb_sunny_outlined : Icons.nights_stay_outlined,
                color: color,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  side.teamTitleRu,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              Icon(Icons.groups_outlined, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                '${participants.length}${maxParticipants > 0 ? ' / $maxParticipants' : ''}',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (participants.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Пока никого',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 12.5,
              ),
            ),
          )
        else
          for (final p in participants) ...[
            tileBuilder(p, color),
            const SizedBox(height: 6),
          ],
      ],
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.participant,
    required this.accent,
    this.isAssistant = false,
    this.onAssignTap,
  });

  final EventParticipant participant;
  final Color accent;
  final bool isAssistant;
  final VoidCallback? onAssignTap;

  @override
  Widget build(BuildContext context) {
    final p = participant;
    return AppCard(
      padding: EdgeInsets.zero,
      onTap: onAssignTap,
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(AppRadii.card),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                child: Row(
                  children: [
                    _Avatar(
                      url: p.avatarUrl,
                      name: p.nickname ?? '?',
                      accent: accent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  p.nickname ?? 'Боец',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isAssistant) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.accentSoft,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: AppColors.accentDim,
                                    ),
                                  ),
                                  child: const Text(
                                    'Помощник',
                                    style: TextStyle(
                                      color: AppColors.accent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
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
              ),
            ),
          ],
        ),
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
  const _Avatar({
    required this.url,
    required this.name,
    this.accent = AppColors.accent,
  });

  final String? url;
  final String name;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceElevated,
        border: Border.all(color: accent.withValues(alpha: 0.45)),
        image: url != null
            ? DecorationImage(image: NetworkImage(url!), fit: BoxFit.cover)
            : null,
      ),
      alignment: Alignment.center,
      child: url == null
          ? Text(
              letter,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w800,
              ),
            )
          : null,
    );
  }
}
