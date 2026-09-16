import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/models/event.dart';

Future<EventSide?> showEventSidePickDialog({
  required BuildContext context,
  required Event event,
}) {
  return showDialog<EventSide>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (context) => EventSidePickDialog(event: event),
  );
}

class EventSidePickDialog extends StatelessWidget {
  const EventSidePickDialog({super.key, required this.event});

  final Event event;

  @override
  Widget build(BuildContext context) {
    final max = event.maxParticipants;
    final total = event.participantsCount;
    final light = event.lightParticipantsCount;
    final dark = event.darkParticipantsCount;

    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  tooltip: 'Закрыть',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ),
              const Icon(
                Icons.flag_outlined,
                color: AppColors.accent,
                size: 28,
              ),
              const SizedBox(height: 8),
              Text(
                'ВЫБЕРИТЕ СТОРОНУ',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      fontSize: 17,
                    ),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Участвуйте в игре в составе одной из команд. '
                  'После выбора вы сможете изменить сторону только '
                  'с разрешения организатора.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 280,
                child: Row(
                  children: [
                    Expanded(
                      child: _SideCard(
                        side: EventSide.light,
                        count: light,
                        maxParticipants: max,
                        onTap: () =>
                            Navigator.pop(context, EventSide.light),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SideCard(
                        side: EventSide.dark,
                        count: dark,
                        maxParticipants: max,
                        onTap: () =>
                            Navigator.pop(context, EventSide.dark),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.cardSoft,
                  borderRadius: BorderRadius.circular(AppRadii.chip),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.groups_outlined,
                          size: 16,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Всего участников: $total',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Вы можете изменить сторону до начала игры '
                      'только через организатора.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Отмена'),
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

class _SideCard extends StatelessWidget {
  const _SideCard({
    required this.side,
    required this.count,
    required this.maxParticipants,
    required this.onTap,
  });

  final EventSide side;
  final int count;
  final int maxParticipants;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isLight = side == EventSide.light;
    final color = isLight ? AppColors.accent : AppColors.danger;
    final progress = maxParticipants <= 0
        ? 0.0
        : (count / maxParticipants).clamp(0.0, 1.0);
    final percent = (progress * 100).round();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.85), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.18),
                blurRadius: 10,
                spreadRadius: 0.5,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10.5),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  side.assetImage,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x00000000),
                        Color(0x66000000),
                        Color(0xE6000000),
                      ],
                      stops: [0.35, 0.62, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.groups, size: 14, color: color),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '$count / $maxParticipants',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Text(
                            '$percent%',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 5,
                          backgroundColor: Colors.white.withValues(alpha: 0.12),
                          color: color,
                        ),
                      ),
                    ],
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
