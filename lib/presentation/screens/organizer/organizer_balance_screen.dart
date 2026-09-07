import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../domain/models/organizer_wallet.dart';
import '../../../presentation/providers/organizer_wallet_providers.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/feedback.dart';

class OrganizerBalanceScreen extends ConsumerWidget {
  const OrganizerBalanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletAsync = ref.watch(organizerWalletProvider);
    final txAsync = ref.watch(organizerTransactionsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Баланс')),
      body: RefreshIndicator(
        color: AppColors.accent,
        onRefresh: () async {
          await ref.read(organizerWalletProvider.notifier).refresh();
          await ref.read(organizerTransactionsProvider.notifier).refresh();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            walletAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => AsyncErrorRetry(
                message: ErrorMapper.map(e),
                onRetry: () =>
                    ref.read(organizerWalletProvider.notifier).refresh(),
              ),
              data: (wallet) => AppCard(
                accentBorder: true,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle(title: 'Баланс'),
                    Text(
                      wallet?.balanceLabel ?? '0 CR',
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Начисление за подтверждённое присутствие',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            const SectionTitle(title: 'История операций'),
            txAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text(
                ErrorMapper.map(e),
                style: const TextStyle(color: AppColors.danger),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const EmptyStateCard(
                    title: 'Пока пусто',
                    subtitle: 'Подтвердите участников — появятся начисления',
                  );
                }
                return Column(
                  children: [
                    for (final tx in items) ...[
                      _TxTile(tx: tx),
                      const SizedBox(height: 6),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TxTile extends StatelessWidget {
  const _TxTile({required this.tx});

  final OrganizerTransaction tx;

  @override
  Widget build(BuildContext context) {
    final time = _formatWhen(tx.createdAt);
    final title = tx.eventTitle ?? 'Операция';
    final subtitle = tx.participantNickname ?? tx.description;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  time,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          Text(
            tx.amountLabel,
            style: TextStyle(
              color: tx.type.isCredit ? AppColors.accent : AppColors.danger,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  String _formatWhen(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final time = DateFormat('HH:mm', 'ru').format(local);
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return 'Сегодня, $time';
    }
    return DateFormat('d MMM, HH:mm', 'ru').format(local);
  }
}
