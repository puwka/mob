import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../domain/models/conversation.dart';
import '../../../presentation/providers/chat_providers.dart';
import '../../../presentation/providers/dating_providers.dart';
import '../../../widgets/feedback.dart';

class DatingMatchesScreen extends ConsumerWidget {
  const DatingMatchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(datingMatchesProvider);
    final dateFmt = DateFormat('d MMM yyyy', 'ru');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Совпадения')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: AsyncErrorRetry(
            message: ErrorMapper.map(e),
            onRetry: () => ref.read(datingMatchesProvider.notifier).refresh(),
          ),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: EmptyStateCard(
                  title: 'Пока нет совпадений',
                  subtitle: 'Лайкните кого-то взаимно — и здесь появится чат',
                  icon: Icons.handshake_outlined,
                ),
              ),
            );
          }

          return RefreshIndicator(
            color: AppColors.accent,
            onRefresh: () =>
                ref.read(datingMatchesProvider.notifier).refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: list.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final m = list[index];
                return Material(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    onTap: m.conversationId == null
                        ? null
                        : () {
                            ref.read(chatFolderProvider.notifier).state =
                                ConversationType.dating;
                            context.push(
                              '/main/chats/${m.conversationId}',
                            );
                          },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadii.card),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          ClipOval(
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: m.avatarUrl != null &&
                                      m.avatarUrl!.isNotEmpty
                                  ? Image.network(
                                      m.avatarUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              const ColoredBox(
                                        color: AppColors.surfaceElevated,
                                        child: Icon(
                                          Icons.person_outline,
                                          color: AppColors.textTertiary,
                                        ),
                                      ),
                                    )
                                  : const ColoredBox(
                                      color: AppColors.surfaceElevated,
                                      child: Icon(
                                        Icons.person_outline,
                                        color: AppColors.textTertiary,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.nickname,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  m.city,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  dateFmt.format(m.createdAt.toLocal()),
                                  style: const TextStyle(
                                    color: AppColors.textTertiary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chat_bubble_outline,
                            size: 18,
                            color: AppColors.accent,
                          ),
                        ],
                      ),
                    ),
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
