import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../domain/models/conversation.dart';
import '../../../domain/models/event.dart';
import '../../../domain/models/event_rules.dart';
import '../../../domain/models/polygon.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../presentation/providers/chat_providers.dart';
import '../../../presentation/providers/event_rules_providers.dart';
import '../../../presentation/providers/events_provider.dart';
import '../../../presentation/providers/organizer_events_providers.dart';
import '../../../presentation/providers/polygon_providers.dart';
import '../../../presentation/providers/repository_providers.dart';
import '../../../services/event_image_storage_service.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_network_image.dart';
import '../../../widgets/app_text_field.dart';
import '../../../widgets/city_picker.dart';
import '../../../widgets/feedback.dart';
import 'map_location_picker_screen.dart';

class CreateEventScreen extends ConsumerStatefulWidget {
  const CreateEventScreen({super.key, this.eventId});

  /// When set, form edits an existing event.
  final String? eventId;

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
  final _rulesBody = TextEditingController();
  final _radioFrequency = TextEditingController();

  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 18, minute: 0);
  final List<_LocalEventImage> _images = [];
  final List<EventImage> _removedExisting = [];
  PolygonVenue? _polygon;
  EventRulesTemplate? _rules;
  var _clearRules = false;
  var _hasDetachedRules = false;
  var _rulesDirty = false;
  double? _lat;
  double? _lng;
  EventStatus? _status;
  var _saving = false;
  var _loadingEvent = false;
  String? _error;

  bool get _isEdit => widget.eventId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _loadingEvent = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadExisting());
    } else {
      final city = ref.read(currentProfileProvider).valueOrNull?.city;
      if (city != null && city.isNotEmpty) {
        _city.text = city;
      }
    }
  }

  Future<void> _loadExisting() async {
    final id = widget.eventId;
    if (id == null) return;
    try {
      final event = await ref.read(eventRepositoryProvider).fetchById(id);
      if (!mounted) return;

      PolygonVenue? polygon;
      if (event.polygonId != null) {
        final list = ref.read(myPolygonsProvider).valueOrNull ?? const [];
        for (final p in list) {
          if (p.id == event.polygonId) {
            polygon = p;
            break;
          }
        }
        if (polygon == null) {
          await ref.read(myPolygonsProvider.notifier).refresh();
          final refreshed =
              ref.read(myPolygonsProvider).valueOrNull ?? const [];
          for (final p in refreshed) {
            if (p.id == event.polygonId) {
              polygon = p;
              break;
            }
          }
        }
      }

      EventRulesTemplate? rules;
      var detachedRules = false;
      if (event.rulesId != null) {
        var list = ref.read(myEventRulesProvider).valueOrNull ?? const [];
        for (final r in list) {
          if (r.id == event.rulesId) {
            rules = r;
            break;
          }
        }
        if (rules == null) {
          await ref.read(myEventRulesProvider.notifier).refresh();
          list = ref.read(myEventRulesProvider).valueOrNull ?? const [];
          for (final r in list) {
            if (r.id == event.rulesId) {
              rules = r;
              break;
            }
          }
        }
      }
      if (rules == null && event.hasRules) {
        detachedRules = true;
      }

      final local = event.eventDate.toLocal();
      setState(() {
        _title.text = event.title;
        _description.text = event.description;
        _city.text = event.city;
        _location.text = event.location;
        _limit.text = '${event.maxParticipants}';
        _date = DateTime(local.year, local.month, local.day);
        _time = TimeOfDay(hour: local.hour, minute: local.minute);
        _images
          ..clear()
          ..addAll([
            for (final img in event.images)
              _LocalEventImage(bytes: Uint8List(0), existing: img),
          ]);
        if (_images.isEmpty &&
            event.imageUrl != null &&
            event.imageUrl!.trim().isNotEmpty) {
          _images.add(
            _LocalEventImage(
              bytes: Uint8List(0),
              existing: EventImage(
                id: 'legacy-cover',
                eventId: event.id,
                url: event.imageUrl!,
                sortOrder: 0,
              ),
            ),
          );
        }
        _removedExisting.clear();
        _polygon = polygon;
        _rules = rules;
        _clearRules = false;
        _hasDetachedRules = detachedRules;
        _rulesDirty = detachedRules || rules != null;
        _rulesBody.text = event.rulesText;
        _radioFrequency.text = event.radioFrequency;
        _lat = event.latitude;
        _lng = event.longitude;
        _status = event.status;
        _loadingEvent = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingEvent = false;
        _error = ErrorMapper.map(e);
      });
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _city.dispose();
    _location.dispose();
    _limit.dispose();
    _rulesBody.dispose();
    _radioFrequency.dispose();
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

  Future<void> _pickRules() async {
    final templates = ref.read(myEventRulesProvider).valueOrNull ?? const [];
    if (templates.isEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Нет шаблонов'),
          content: const Text(
            'Сначала создайте шаблон правил во вкладке организатора.',
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
        await context.push('/main/profile/organizer/rules/create');
        await ref.read(myEventRulesProvider.notifier).refresh();
      }
      return;
    }

    final selected = await showModalBottomSheet<Object>(
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
                'Шаблон правил',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (_rules != null || (_hasDetachedRules && !_clearRules))
              ListTile(
                leading: const Icon(Icons.clear, color: AppColors.textTertiary),
                title: const Text('Без правил'),
                onTap: () => Navigator.pop(context, 'clear'),
              ),
            for (final t in templates)
              ListTile(
                leading:
                    const Icon(Icons.gavel_outlined, color: AppColors.accent),
                title: Text(t.title),
                subtitle: Text(
                  t.shortBody,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(context, t),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    if (selected == 'clear') {
      setState(() {
        _rules = null;
        _clearRules = true;
        _hasDetachedRules = false;
        _rulesDirty = false;
        _rulesBody.clear();
      });
      return;
    }
    if (selected is EventRulesTemplate) {
      setState(() {
        _rules = selected;
        _clearRules = false;
        _hasDetachedRules = false;
        _rulesDirty = true;
        _rulesBody.text = selected.body;
      });
      await _editRulesBody(fromTemplate: true);
    }
  }

  bool get _hasRulesDraft =>
      !_clearRules && _rulesBody.text.trim().isNotEmpty;

  Future<void> _onRulesCardTap() async {
    if (_hasRulesDraft) {
      final action = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: AppColors.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        ),
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text(
                  'Правила мероприятия',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: AppColors.accent),
                title: const Text('Изменить текст'),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
              ListTile(
                leading:
                    const Icon(Icons.folder_open_outlined, color: AppColors.accent),
                title: const Text('Другой шаблон'),
                onTap: () => Navigator.pop(context, 'pick'),
              ),
              ListTile(
                leading: const Icon(Icons.clear, color: AppColors.textTertiary),
                title: const Text('Убрать правила'),
                onTap: () => Navigator.pop(context, 'clear'),
              ),
            ],
          ),
        ),
      );
      if (!mounted || action == null) return;
      if (action == 'edit') {
        await _editRulesBody();
      } else if (action == 'pick') {
        await _pickRules();
      } else if (action == 'clear') {
        setState(() {
          _rules = null;
          _clearRules = true;
          _hasDetachedRules = false;
          _rulesDirty = false;
          _rulesBody.clear();
        });
      }
      return;
    }
    await _pickRules();
  }

  Future<void> _editRulesBody({bool fromTemplate = false}) async {
    final draft = TextEditingController(text: _rulesBody.text);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (context) {
        final bottom = MediaQuery.viewInsetsOf(context).bottom;
        final height = MediaQuery.sizeOf(context).height * 0.78;
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: SizedBox(
            height: height,
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            fromTemplate
                                ? 'Правила: ${_rules?.title ?? 'шаблон'}'
                                : 'Текст правил',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Закрыть',
                          onPressed: () => Navigator.pop(context, false),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  if (fromTemplate)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        'Можно изменить текст только для этого мероприятия. Шаблон не изменится.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ),
                  const Divider(height: 1),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: TextField(
                        controller: draft,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: const InputDecoration(
                          hintText: 'Введите правила мероприятия',
                          border: InputBorder.none,
                        ),
                        style: const TextStyle(fontSize: 14.5, height: 1.4),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: AppButton(
                      label: 'Готово',
                      onPressed: () => Navigator.pop(context, true),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    final text = draft.text;
    draft.dispose();
    if (!mounted) return;
    if (saved == true) {
      setState(() {
        _rulesBody.text = text;
        _rulesDirty = text.trim().isNotEmpty;
        _clearRules = text.trim().isEmpty;
        if (text.trim().isEmpty) {
          _rules = null;
          _hasDetachedRules = false;
        }
      });
    } else if (fromTemplate && _rulesBody.text.trim().isEmpty) {
      // cancelled right after picking empty — keep template body
      setState(() => _rulesBody.text = _rules?.body ?? '');
    }
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
    final now = DateTime.now();
    final first = _isEdit
        ? (_date.isBefore(now) ? _date : DateTime(now.year, now.month, now.day))
        : DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(first) ? first : _date,
      firstDate: first,
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

  Future<void> _pickPhotos() async {
    final max = EventImageStorageService.maxImages;
    final left = max - _images.length;
    if (left <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Максимум $max фото'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final files = await ImagePicker().pickMultiImage(
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 90,
      limit: left,
    );
    if (files.isEmpty) return;

    for (final file in files.take(left)) {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) continue;
      if (!mounted) return;
      setState(() => _images.add(_LocalEventImage(bytes: bytes)));
    }
  }

  Future<void> _syncEventImages({
    required String eventId,
    required String organizerId,
  }) async {
    final repo = ref.read(eventRepositoryProvider);
    final storage = ref.read(eventImageStorageServiceProvider);

    for (final removed in _removedExisting) {
      if (removed.id == 'legacy-cover') {
        await repo.setEventImageUrl(eventId: eventId, imageUrl: null);
        continue;
      }
      await repo.deleteEventImage(removed.id);
      try {
        await storage.deleteByUrl(removed.url);
      } catch (_) {}
    }

    var order = 0;
    for (final img in _images) {
      if (img.existing != null) {
        if (img.existing!.id == 'legacy-cover') {
          await repo.addEventImage(
            eventId: eventId,
            url: img.existing!.url,
            sortOrder: order,
          );
        }
        order++;
        continue;
      }
      final url = await storage.uploadImage(
        organizerId: organizerId,
        eventId: eventId,
        bytes: img.bytes,
        sortOrder: order,
      );
      await repo.addEventImage(
        eventId: eventId,
        url: url,
        sortOrder: order,
      );
      order++;
    }

    final refreshed = await repo.fetchImages(eventId);
    if (refreshed.isNotEmpty) {
      await repo.reorderEventImages(refreshed);
    } else if (_images.isEmpty) {
      await repo.setEventImageUrl(eventId: eventId, imageUrl: null);
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    final isOrg =
        ref.read(currentProfileProvider).valueOrNull?.isOrganizer ?? false;
    if (!isOrg) {
      setState(
        () => _error = _isEdit
            ? 'Только организатор может изменять мероприятия'
            : 'Только организатор может создавать мероприятия',
      );
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
      final eventId = widget.eventId;

      if (eventId != null) {
        await repo.updateEvent(
          eventId: eventId,
          title: _title.text.trim(),
          description: _description.text.trim(),
          city: _city.text.trim(),
          location: _location.text.trim(),
          eventDate: eventDate,
          maxParticipants: limit,
          status: _status,
          polygonId: _polygon?.id,
          latitude: _lat,
          longitude: _lng,
          rulesId: _rules?.id,
          clearRules: _clearRules || !_hasRulesDraft,
          rulesText: _rulesBody.text.trim(),
          setRulesText: _rulesDirty || _hasRulesDraft || _clearRules,
          radioFrequency: _radioFrequency.text.trim(),
        );

        if (uid != null) {
          await _syncEventImages(eventId: eventId, organizerId: uid);
        }

        ref.invalidate(eventDetailsProvider(eventId));
        ref.invalidate(myOrganizerEventsProvider);
        ref.invalidate(eventsListProvider);
        ref.invalidate(conversationsByTypeProvider(ConversationType.event));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Мероприятие обновлено')),
        );
        context.pop();
      } else {
        final createdId = await repo.createEvent(
          title: _title.text.trim(),
          description: _description.text.trim(),
          city: _city.text.trim(),
          location: _location.text.trim(),
          eventDate: eventDate,
          maxParticipants: limit,
          polygonId: _polygon?.id,
          latitude: _lat,
          longitude: _lng,
          rulesId: _rules?.id,
          rulesText: _hasRulesDraft ? _rulesBody.text.trim() : '',
          radioFrequency: _radioFrequency.text.trim(),
        );

        if (uid != null) {
          await _syncEventImages(eventId: createdId, organizerId: uid);
        }

        ref.invalidate(myOrganizerEventsProvider);
        ref.invalidate(conversationsByTypeProvider(ConversationType.event));
        if (!mounted) return;
        context.go('/main/profile/organizer/events/$createdId');
      }
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
      appBar: AppBar(
        title: Text(_isEdit ? 'Изменить мероприятие' : 'Создать мероприятие'),
      ),
      body: _loadingEvent
          ? const Center(child: CircularProgressIndicator())
          : Form(
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
            AppCard(
              onTap: _onRulesCardTap,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Row(
                children: [
                  const Icon(Icons.gavel_outlined, color: AppColors.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _hasRulesDraft
                              ? (_rules != null
                                  ? 'Правила: ${_rules!.title}'
                                  : 'Правила мероприятия')
                              : 'Правила (не выбраны)',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (_hasRulesDraft) ...[
                          const SizedBox(height: 3),
                          Text(
                            _rulesBody.text.trim().length > 80
                                ? '${_rulesBody.text.trim().substring(0, 77)}…'
                                : _rulesBody.text.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12.5,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.textTertiary),
                ],
              ),
            ),
            const SizedBox(height: 10),
            AppTextField(
              controller: _radioFrequency,
              label: 'Частота рации',
              hint: 'Например: 446.00625 или PMR 1',
              prefixIcon: Icons.cell_tower_outlined,
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
            const SectionTitle(title: 'Фотографии'),
            Text(
              'Первое фото — обложка (16:9). До ${EventImageStorageService.maxImages} фото, удерживайте для сортировки.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                  ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 88,
              child: ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                buildDefaultDragHandles: false,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = _images.removeAt(oldIndex);
                    _images.insert(newIndex, item);
                  });
                },
                itemCount: _images.length + 1,
                itemBuilder: (context, index) {
                  if (index == _images.length) {
                    return Padding(
                      key: const ValueKey('add'),
                      padding: const EdgeInsets.only(right: 8),
                      child: InkWell(
                        onTap: _saving ? null : _pickPhotos,
                        borderRadius: BorderRadius.circular(AppRadii.badge),
                        child: Container(
                          width: 88,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius:
                                BorderRadius.circular(AppRadii.badge),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Icon(
                            Icons.add_photo_alternate_outlined,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    );
                  }

                  final img = _images[index];
                  return Padding(
                    key: ValueKey(
                      img.existing?.id ??
                          'local-$index-${img.bytes.length}',
                    ),
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        ReorderableDelayedDragStartListener(
                          index: index,
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(AppRadii.badge),
                            child: SizedBox(
                              width: 88,
                              height: 88,
                              child: img.existing != null
                                  ? AppNetworkImage(
                                      url: img.existing!.url,
                                      fit: BoxFit.cover,
                                      width: 88,
                                      height: 88,
                                      memCacheWidth: 200,
                                      debugLabel: 'event-edit-thumb',
                                    )
                                  : Image.memory(
                                      img.bytes,
                                      fit: BoxFit.cover,
                                    ),
                            ),
                          ),
                        ),
                        if (index == 0)
                          Positioned(
                            left: 4,
                            bottom: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.scrim,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Обложка',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: InkWell(
                            onTap: _saving
                                ? null
                                : () => setState(() {
                                      final removed = _images.removeAt(index);
                                      if (removed.existing != null) {
                                        _removedExisting
                                            .add(removed.existing!);
                                      }
                                    }),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: AppColors.scrim,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 14,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
            AppButton(
              label: _isEdit ? 'Сохранить изменения' : 'Создать мероприятие',
              loading: _saving,
              onPressed: _saving ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalEventImage {
  _LocalEventImage({
    required this.bytes,
    this.existing,
  });

  final Uint8List bytes;
  final EventImage? existing;
}
