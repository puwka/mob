import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../domain/models/conversation.dart';
import '../../../presentation/providers/chat_providers.dart';
import '../../../presentation/providers/events_provider.dart';
import '../../../presentation/providers/organizer_events_providers.dart';
import '../../../presentation/providers/repository_providers.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_text_field.dart';
import '../../../widgets/feedback.dart';

class EventReportScreen extends ConsumerStatefulWidget {
  const EventReportScreen({super.key, required this.eventId});

  final String eventId;

  @override
  ConsumerState<EventReportScreen> createState() => _EventReportScreenState();
}

class _EventReportScreenState extends ConsumerState<EventReportScreen> {
  String _winner = 'light';
  final _scoreLight = TextEditingController(text: '0');
  final _scoreDark = TextEditingController(text: '0');
  var _loading = false;
  String? _error;

  @override
  void dispose() {
    _scoreLight.dispose();
    _scoreDark.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _loading = true;
    });

    final light = int.tryParse(_scoreLight.text.trim());
    final dark = int.tryParse(_scoreDark.text.trim());
    if (light == null || dark == null || light < 0 || dark < 0) {
      setState(() {
        _error = 'Укажите корректный счёт';
        _loading = false;
      });
      return;
    }

    try {
      await ref.read(eventRepositoryProvider).submitEventReport(
            eventId: widget.eventId,
            winner: _winner,
            scoreLight: light,
            scoreDark: dark,
          );
      ref.invalidate(eventDetailsProvider(widget.eventId));
      ref.invalidate(myOrganizerEventsProvider);
      ref.invalidate(conversationsByTypeProvider(ConversationType.event));
      if (!mounted) return;
      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Отчёт опубликован в чате'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorMapper.map(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = ref.watch(eventDetailsProvider(widget.eventId)).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Отчёт о игре')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(
            event?.title ?? 'Мероприятие',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Укажите победителя и счёт — итоги появятся в чате мероприятия.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Победитель',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _WinnerChip(
                label: 'Зелёная',
                selected: _winner == 'light',
                color: AppColors.accent,
                onTap: _loading ? null : () => setState(() => _winner = 'light'),
              ),
              _WinnerChip(
                label: 'Красная',
                selected: _winner == 'dark',
                color: AppColors.danger,
                onTap: _loading ? null : () => setState(() => _winner = 'dark'),
              ),
              _WinnerChip(
                label: 'Ничья',
                selected: _winner == 'draw',
                color: AppColors.textSecondary,
                onTap: _loading ? null : () => setState(() => _winner = 'draw'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _scoreLight,
                  label: 'Счёт — зелёная',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  enabled: !_loading,
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(10, 18, 10, 0),
                child: Text(
                  ':',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(
                child: AppTextField(
                  controller: _scoreDark,
                  label: 'Счёт — красная',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  enabled: !_loading,
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: 22),
          AppButton(
            label: 'Опубликовать итоги',
            loading: _loading,
            onPressed: _loading ? null : _submit,
          ),
        ],
      ),
    );
  }
}

class _WinnerChip extends StatelessWidget {
  const _WinnerChip({
    required this.label,
    required this.selected,
    required this.color,
    this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color.withValues(alpha: 0.18) : AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(AppRadii.chip),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.chip),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.chip),
            border: Border.all(
              color: selected ? color : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: selected ? color : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
