import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../domain/models/event_rules.dart';
import '../../../presentation/providers/event_rules_providers.dart';
import '../../../presentation/providers/repository_providers.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_text_field.dart';
import '../../../widgets/feedback.dart';

class EditEventRulesScreen extends ConsumerStatefulWidget {
  const EditEventRulesScreen({super.key, this.initial});

  final EventRulesTemplate? initial;

  bool get isEdit => initial != null;

  @override
  ConsumerState<EditEventRulesScreen> createState() =>
      _EditEventRulesScreenState();
}

class _EditEventRulesScreenState extends ConsumerState<EditEventRulesScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();

  var _saving = false;
  var _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _title.text = initial.title;
      _body.text = initial.body;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final repo = ref.read(eventRulesRepositoryProvider);
      if (widget.isEdit) {
        await repo.update(
          id: widget.initial!.id,
          title: _title.text.trim(),
          body: _body.text.trim(),
        );
      } else {
        await repo.create(
          title: _title.text.trim(),
          body: _body.text.trim(),
        );
      }
      await ref.read(myEventRulesProvider.notifier).refresh();
      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorMapper.map(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Удалить шаблон?'),
        content: const Text(
          'Мероприятия сохранят уже прикреплённый текст правил.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await ref
          .read(eventRulesRepositoryProvider)
          .delete(widget.initial!.id);
      await ref.read(myEventRulesProvider.notifier).refresh();
      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorMapper.map(e));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.isEdit ? 'Правила' : 'Новый шаблон'),
        actions: [
          if (widget.isEdit)
            IconButton(
              tooltip: 'Удалить',
              onPressed: _saving || _deleting ? null : _delete,
              icon: _deleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: 10),
            ],
            AppTextField(
              controller: _title,
              label: 'Название шаблона',
              validator: (v) => (v == null || v.trim().length < 2)
                  ? 'Введите название'
                  : null,
            ),
            const SizedBox(height: 10),
            AppTextField(
              controller: _body,
              label: 'Текст правил',
              maxLines: 14,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Введите текст правил'
                  : null,
            ),
            const SizedBox(height: 18),
            AppButton(
              label: widget.isEdit ? 'Сохранить' : 'Создать',
              onPressed: _saving || _deleting ? null : _submit,
              loading: _saving,
            ),
          ],
        ),
      ),
    );
  }
}
