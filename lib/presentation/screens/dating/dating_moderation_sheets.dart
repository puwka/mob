import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../presentation/providers/repository_providers.dart';

Future<bool> confirmBlockUser(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.card,
      title: const Text('Заблокировать?'),
      content: const Text(
        'Пользователь исчезнет из знакомств и совпадений. '
        'Отправка сообщений будет запрещена.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          child: const Text('Заблокировать'),
        ),
      ],
    ),
  );
  return result == true;
}

const _reportReasons = <String>[
  'Спам',
  'Оскорбления',
  'Фейковый профиль',
  'Неуместный контент',
  'Другое',
];

Future<bool> showReportUserSheet(
  BuildContext context, {
  required String targetUserId,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    builder: (context) => _ReportSheet(targetUserId: targetUserId),
  );
  return result == true;
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({required this.targetUserId});

  final String targetUserId;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  String _reason = _reportReasons.first;
  final _desc = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(datingRepositoryProvider).reportUser(
            targetUserId: widget.targetUserId,
            reason: _reason,
            description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
          );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorMapper.map(e))),
      );
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Пожаловаться',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final reason in _reportReasons)
                ChoiceChip(
                  label: Text(reason),
                  selected: _reason == reason,
                  onSelected: (_) => setState(() => _reason = reason),
                  selectedColor: AppColors.accentSoft,
                  labelStyle: TextStyle(
                    color: _reason == reason
                        ? AppColors.accent
                        : AppColors.textSecondary,
                    fontSize: 13,
                  ),
                  side: BorderSide(
                    color: _reason == reason
                        ? AppColors.accentDim
                        : AppColors.border,
                  ),
                  backgroundColor: AppColors.surfaceElevated,
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(
              hintText: 'Комментарий (необязательно)',
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 46,
            child: ElevatedButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Отправить'),
            ),
          ),
        ],
      ),
    );
  }
}
