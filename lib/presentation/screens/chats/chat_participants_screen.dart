import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../presentation/providers/chat_providers.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/feedback.dart';

class ChatParticipantsScreen extends ConsumerWidget {
  const ChatParticipantsScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(conversationParticipantsProvider(conversationId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Участники')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: AsyncErrorRetry(
            message: ErrorMapper.map(e),
            onRetry: () =>
                ref.invalidate(conversationParticipantsProvider(conversationId)),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: EmptyStateCard(
                title: 'Нет участников',
                subtitle: 'В этом чате пока никого нет',
              ),
            );
          }

          return RefreshIndicator(
            color: AppColors.accent,
            onRefresh: () async {
              ref.invalidate(conversationParticipantsProvider(conversationId));
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final p = items[index];
                return AppCard(
                  padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                  onTap: () =>
                      context.push('/main/profile/user/${p.userId}'),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: AppColors.surfaceElevated,
                        backgroundImage: p.avatarUrl != null &&
                                p.avatarUrl!.isNotEmpty
                            ? NetworkImage(p.avatarUrl!)
                            : null,
                        child: p.avatarUrl == null || p.avatarUrl!.isEmpty
                            ? Text(
                                p.nickname.isNotEmpty
                                    ? p.nickname[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.nickname,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            if (p.roleLabel != null)
                              Text(
                                p.roleLabel!,
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
                        size: 20,
                      ),
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
