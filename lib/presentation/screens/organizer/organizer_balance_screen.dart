import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../domain/models/organizer_wallet.dart';
import '../../../presentation/providers/organizer_wallet_providers.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_text_field.dart';
import '../../../widgets/feedback.dart';

class OrganizerBalanceScreen extends ConsumerStatefulWidget {
  const OrganizerBalanceScreen({super.key});

  @override
  ConsumerState<OrganizerBalanceScreen> createState() =>
      _OrganizerBalanceScreenState();
}

class _OrganizerBalanceScreenState
    extends ConsumerState<OrganizerBalanceScreen> {
  bool _submitting = false;

  Future<void> _openWithdrawDialog(OrganizerWallet? wallet) async {
    final balance = wallet?.balance ?? 0;
    if (balance <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Недостаточно средств для вывода')),
      );
      return;
    }

    final repo = ref.read(organizerWalletRepositoryProvider);
    final minAmount = await repo.fetchMinWithdrawalAmount();
    final fee = await repo.fetchWithdrawalFee();
    if (!mounted) return;

    final amountCtrl = TextEditingController();
    final detailsCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Заявка на вывод'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Доступно: ${wallet?.balanceLabel ?? '0 CR'}'
                    '${fee > 0 ? '\nКомиссия: $fee CR' : ''}'
                    '\nМинимум: $minAmount CR',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: amountCtrl,
                    label: 'Сумма',
                    hint: 'Сколько вывести',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    validator: (v) {
                      final raw = (v ?? '').trim().replaceAll(',', '.');
                      final n = num.tryParse(raw);
                      if (n == null || n <= 0) return 'Укажите сумму';
                      if (n < minAmount) {
                        return 'Минимум $minAmount CR';
                      }
                      final total = n + fee;
                      if (total > balance) {
                        return 'Недостаточно средств'
                            '${fee > 0 ? ' (с комиссией $total)' : ''}';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: detailsCtrl,
                    label: 'Реквизиты',
                    hint: 'Карта / телефон / банк',
                    maxLines: 3,
                    minLines: 2,
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.length < 5) {
                        return 'Укажите реквизиты для выплаты';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                Navigator.pop(context, true);
              },
              child: const Text('Отправить'),
            ),
          ],
        );
      },
    );

    if (ok != true || !mounted) {
      amountCtrl.dispose();
      detailsCtrl.dispose();
      return;
    }

    final amount = num.parse(amountCtrl.text.trim().replaceAll(',', '.'));
    final details = detailsCtrl.text.trim();
    amountCtrl.dispose();
    detailsCtrl.dispose();

    setState(() => _submitting = true);
    try {
      await ref.read(organizerWithdrawalsProvider.notifier).request(
            amount: amount,
            paymentDetails: details,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заявка отправлена в админку')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorMapper.map(e))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(organizerWalletProvider);
    final txAsync = ref.watch(organizerTransactionsProvider);
    final wdAsync = ref.watch(organizerWithdrawalsProvider);
    final hasPending = wdAsync.valueOrNull?.any(
          (w) => w.status == WithdrawalStatus.pending,
        ) ??
        false;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Баланс')),
      body: RefreshIndicator(
        color: AppColors.accent,
        onRefresh: () async {
          await ref.read(organizerWalletProvider.notifier).refresh();
          await ref.read(organizerTransactionsProvider.notifier).refresh();
          await ref.read(organizerWithdrawalsProvider.notifier).refresh();
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
                    const SizedBox(height: 14),
                    AppButton(
                      label: hasPending
                          ? 'Заявка на проверке'
                          : 'Вывести средства',
                      loading: _submitting,
                      onPressed: _submitting || hasPending
                          ? null
                          : () => _openWithdrawDialog(wallet),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            const SectionTitle(title: 'Заявки на вывод'),
            wdAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => Text(
                ErrorMapper.map(e),
                style: const TextStyle(color: AppColors.danger),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Пока нет заявок',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 13,
                      ),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final item in items) ...[
                      _WithdrawalTile(item: item),
                      const SizedBox(height: 6),
                    ],
                  ],
                );
              },
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

class _WithdrawalTile extends StatelessWidget {
  const _WithdrawalTile({required this.item});

  final OrganizerWithdrawalRequest item;

  Color get _statusColor => switch (item.status) {
        WithdrawalStatus.pending => AppColors.warning,
        WithdrawalStatus.approved => AppColors.accent,
        WithdrawalStatus.rejected => AppColors.danger,
        WithdrawalStatus.cancelled => AppColors.textTertiary,
      };

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('d MMM, HH:mm', 'ru').format(item.createdAt.toLocal());
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.amountLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                item.status.labelRu,
                style: TextStyle(
                  color: _statusColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            item.paymentDetails,
            maxLines: 2,
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
          if (item.adminNote != null && item.adminNote!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Комментарий: ${item.adminNote}',
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 12,
              ),
            ),
          ],
        ],
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
