import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../domain/models/event.dart';
import '../../../presentation/providers/offline_qr_providers.dart';
import '../../../presentation/providers/organizer_events_providers.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/feedback.dart';

/// Pick an active event, then open the QR scanner.
class OrganizerScannerPickScreen extends ConsumerWidget {
  const OrganizerScannerPickScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myOrganizerEventsProvider);
    final pending = ref.watch(pendingAttendanceCountProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Сканер QR')),
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
          final active =
              events.where((e) => e.status == EventStatus.active).toList();
          if (active.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: EmptyStateCard(
                title: 'Нет активных мероприятий',
                subtitle: 'Создайте мероприятие, чтобы сканировать участников',
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const Text(
                'Выберите мероприятие для сканирования. '
                'Перед выездом на полигон откройте сканер при интернете — '
                'список участников сохранится офлайн.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              if (pending > 0) ...[
                const SizedBox(height: 10),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.cloud_upload_outlined,
                        color: AppColors.accent,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Офлайн-сканов ждёт синхронизации: $pending',
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              for (final e in active) ...[
                AppCard(
                  onTap: () => context.push(
                    '/main/profile/organizer/events/${e.id}/scanner',
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.qr_code_scanner,
                        color: AppColors.accent,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.title,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              '${e.city} · ${e.participantsCount}/${e.maxParticipants}',
                              style: const TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: AppColors.textTertiary,
                        size: 18,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    );
  }
}
