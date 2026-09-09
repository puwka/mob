import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../domain/models/polygon.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../presentation/providers/polygon_providers.dart';
import '../../../presentation/providers/repository_providers.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_text_field.dart';
import '../../../widgets/city_picker.dart';
import '../../../widgets/feedback.dart';
import 'map_location_picker_screen.dart';

class EditPolygonScreen extends ConsumerStatefulWidget {
  const EditPolygonScreen({super.key, this.initial});

  final PolygonVenue? initial;

  bool get isEdit => initial != null;

  @override
  ConsumerState<EditPolygonScreen> createState() => _EditPolygonScreenState();
}

class _EditPolygonScreenState extends ConsumerState<EditPolygonScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _address = TextEditingController();

  double? _lat;
  double? _lng;
  var _saving = false;
  var _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _name.text = initial.name;
      _city.text = initial.city;
      _address.text = initial.address;
      _lat = initial.latitude;
      _lng = initial.longitude;
    } else {
      final city = ref.read(currentProfileProvider).valueOrNull?.city;
      if (city != null) _city.text = city;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _pickCity() async {
    final city = await showCityPicker(context, selected: _city.text);
    if (city != null) setState(() => _city.text = city);
  }

  Future<void> _pickMap() async {
    final result = await openMapLocationPicker(
      context,
      latitude: _lat,
      longitude: _lng,
      address: _address.text,
      title: 'Адрес полигона',
    );
    if (result == null || !mounted) return;
    setState(() {
      _lat = result.latitude;
      _lng = result.longitude;
      if (result.address != null && result.address!.isNotEmpty) {
        _address.text = result.address!;
      }
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (_lat == null || _lng == null) {
      setState(() => _error = 'Укажите точку на карте');
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(polygonRepositoryProvider);
      if (widget.isEdit) {
        await repo.update(
          id: widget.initial!.id,
          name: _name.text.trim(),
          city: _city.text.trim(),
          address: _address.text.trim(),
          latitude: _lat!,
          longitude: _lng!,
        );
      } else {
        await repo.create(
          name: _name.text.trim(),
          city: _city.text.trim(),
          address: _address.text.trim(),
          latitude: _lat!,
          longitude: _lng!,
        );
      }
      await ref.read(myPolygonsProvider.notifier).refresh();
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
        title: const Text('Удалить полигон?'),
        content: const Text(
          'Мероприятия сохранят координаты, но ссылка на полигон пропадёт.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _deleting = true);
    try {
      await ref.read(polygonRepositoryProvider).delete(widget.initial!.id);
      await ref.read(myPolygonsProvider.notifier).refresh();
      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = ErrorMapper.map(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPin = _lat != null && _lng != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.isEdit ? 'Редактировать полигон' : 'Новый полигон'),
        actions: [
          if (widget.isEdit)
            IconButton(
              tooltip: 'Удалить',
              onPressed: _deleting ? null : _delete,
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
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
              controller: _name,
              label: 'Название',
              hint: 'Полигон Северный',
              validator: (v) =>
                  (v == null || v.trim().length < 2) ? 'Введите название' : null,
            ),
            const SizedBox(height: 10),
            AppTextField(
              controller: _city,
              label: 'Город',
              readOnly: true,
              onTap: _pickCity,
              prefixIcon: Icons.location_city_outlined,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Выберите город' : null,
            ),
            const SizedBox(height: 10),
            AppTextField(
              controller: _address,
              label: 'Адрес',
              maxLines: 2,
              validator: (v) =>
                  (v == null || v.trim().length < 2) ? 'Укажите адрес' : null,
            ),
            const SizedBox(height: 12),
            const SectionTitle(title: 'Карта'),
            AppCard(
              onTap: _pickMap,
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
              child: Row(
                children: [
                  Icon(
                    hasPin ? Icons.place : Icons.add_location_alt_outlined,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasPin ? 'Точка выбрана' : 'Указать на карте',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (hasPin)
                          Text(
                            '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.textTertiary),
                ],
              ),
            ),
            const SizedBox(height: 18),
            AppButton(
              label: widget.isEdit ? 'Сохранить' : 'Создать полигон',
              loading: _saving,
              onPressed: _saving || _deleting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
