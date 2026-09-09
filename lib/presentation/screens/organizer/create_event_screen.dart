import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../core/utils/event_cover.dart';
import '../../../domain/models/conversation.dart';
import '../../../domain/models/polygon.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../presentation/providers/chat_providers.dart';
import '../../../presentation/providers/organizer_events_providers.dart';
import '../../../presentation/providers/polygon_providers.dart';
import '../../../presentation/providers/repository_providers.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_text_field.dart';
import '../../../widgets/city_picker.dart';
import '../../../widgets/feedback.dart';
import 'map_location_picker_screen.dart';

class CreateEventScreen extends ConsumerStatefulWidget {
  const CreateEventScreen({super.key});

  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _city = TextEditingController();
  final _location = TextEditingController();
  final _limit = TextEditingController(text: '50');

  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 18, minute: 0);
  Uint8List? _photoBytes;
  PolygonVenue? _polygon;
  double? _lat;
  double? _lng;
  var _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final city = ref.read(currentProfileProvider).valueOrNull?.city;
    if (city != null && city.isNotEmpty) {
      _city.text = city;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _city.dispose();
    _location.dispose();
    _limit.dispose();
    super.dispose();
  }

  Future<void> _pickCity() async {
    final city = await showCityPicker(context, selected: _city.text);
    if (city != null) setState(() => _city.text = city);
  }

  Future<void> _pickPolygon() async {
    final polygons = ref.read(myPolygonsProvider).valueOrNull ?? const [];
    if (polygons.isEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Нет полигонов'),
          content: const Text(
            'Сначала создайте полигон с адресом на карте.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Создать'),
            ),
          ],
        ),
      );
      if (go == true && mounted) {
        await context.push('/main/profile/organizer/polygons/create');
        await ref.read(myPolygonsProvider.notifier).refresh();
      }
      return;
    }

    final selected = await showModalBottomSheet<PolygonVenue>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'Выберите полигон',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            for (final p in polygons)
              ListTile(
                leading: const Icon(Icons.map_outlined, color: AppColors.accent),
                title: Text(p.name),
                subtitle: Text('${p.city} · ${p.address}'),
                onTap: () => Navigator.pop(context, p),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _polygon = selected;
      _city.text = selected.city;
      _location.text = selected.mapLabel;
      _lat = selected.latitude;
      _lng = selected.longitude;
    });
  }

  Future<void> _pickMap() async {
    final result = await openMapLocationPicker(
      context,
      latitude: _lat,
      longitude: _lng,
      address: _location.text,
      title: 'Место мероприятия',
    );
    if (result == null || !mounted) return;
    setState(() {
      _polygon = null;
      _lat = result.latitude;
      _lng = result.longitude;
      if (result.address != null && result.address!.isNotEmpty) {
        _location.text = result.address!;
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.accent,
              surface: AppColors.surface,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.accent,
              surface: AppColors.surface,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: EventCoverSpecs.width.toDouble(),
      maxHeight: EventCoverSpecs.height.toDouble() * 2,
      imageQuality: 92,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    try {
      final normalized = await normalizeEventCoverBytes(bytes);
      if (!mounted) return;
      setState(() => _photoBytes = normalized);
    } catch (_) {
      if (!mounted) return;
      setState(() => _photoBytes = bytes);
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    final isOrg =
        ref.read(currentProfileProvider).valueOrNull?.isOrganizer ?? false;
    if (!isOrg) {
      setState(() => _error = 'Только организатор может создавать мероприятия');
      return;
    }

    if (_lat == null || _lng == null) {
      setState(() => _error = 'Укажите полигон или точку на карте');
      return;
    }

    final limit = int.tryParse(_limit.text.trim());
    if (limit == null || limit < 1) {
      setState(() => _error = 'Укажите корректный лимит участников');
      return;
    }

    final eventDate = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );

    setState(() => _saving = true);
    try {
      final repo = ref.read(eventRepositoryProvider);
      final uid = ref.read(currentUserProvider)?.id;
      final eventId = await repo.createEvent(
        title: _title.text.trim(),
        description: _description.text.trim(),
        city: _city.text.trim(),
        location: _location.text.trim(),
        eventDate: eventDate,
        maxParticipants: limit,
        polygonId: _polygon?.id,
        latitude: _lat,
        longitude: _lng,
      );

      if (_photoBytes != null && uid != null) {
        final url = await ref.read(eventImageStorageServiceProvider).uploadCover(
              organizerId: uid,
              eventId: eventId,
              bytes: _photoBytes!,
            );
        await repo.setEventImageUrl(eventId: eventId, imageUrl: url);
      }

      ref.invalidate(myOrganizerEventsProvider);
      ref.invalidate(conversationsByTypeProvider(ConversationType.event));
      if (!mounted) return;
      context.go('/main/profile/organizer/events/$eventId');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorMapper.map(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('d MMMM yyyy', 'ru').format(_date);
    final timeLabel =
        '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';
    final hasPin = _lat != null && _lng != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Создать мероприятие')),
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
              label: 'Название',
              validator: (v) =>
                  (v == null || v.trim().length < 2) ? 'Введите название' : null,
            ),
            const SizedBox(height: 10),
            AppTextField(
              controller: _description,
              label: 'Описание',
              maxLines: 4,
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
            const SizedBox(height: 12),
            const SectionTitle(title: 'Место на карте'),
            AppCard(
              onTap: _pickPolygon,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Row(
                children: [
                  const Icon(Icons.map_outlined, color: AppColors.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _polygon == null
                          ? 'Выбрать полигон'
                          : 'Полигон: ${_polygon!.name}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.textTertiary),
                ],
              ),
            ),
            const SizedBox(height: 8),
            AppCard(
              onTap: _pickMap,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Row(
                children: [
                  Icon(
                    hasPin ? Icons.place : Icons.add_location_alt_outlined,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      hasPin
                          ? 'Точка: ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}'
                          : 'Или указать точку на карте',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.textTertiary),
                ],
              ),
            ),
            const SizedBox(height: 10),
            AppTextField(
              controller: _location,
              label: 'Адрес / место',
              maxLines: 2,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Укажите адрес' : null,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: AppCard(
                    onTap: _pickDate,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Дата',
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateLabel,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppCard(
                    onTap: _pickTime,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Время',
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          timeLabel,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AppTextField(
              controller: _limit,
              label: 'Лимит участников',
              keyboardType: TextInputType.number,
              validator: (v) {
                final n = int.tryParse(v?.trim() ?? '');
                if (n == null || n < 1) return 'Минимум 1';
                return null;
              },
            ),
            const SizedBox(height: 12),
            const SectionTitle(title: 'Фото обложки'),
            Text(
              'Формат ${EventCoverSpecs.width}×${EventCoverSpecs.height} (16:9). '
              'Фото обрежется по центру.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                  ),
            ),
            const SizedBox(height: 8),
            AppCard(
              onTap: _pickPhoto,
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.card - 1),
                child: AspectRatio(
                  aspectRatio: EventCoverSpecs.aspectRatio,
                  child: _photoBytes != null
                      ? Image.memory(_photoBytes!, fit: BoxFit.cover)
                      : const ColoredBox(
                          color: AppColors.surfaceElevated,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.add_photo_alternate_outlined,
                                  color: AppColors.accent,
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Добавить фото 16:9',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            AppButton(
              label: 'Создать мероприятие',
              loading: _saving,
              onPressed: _saving ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
