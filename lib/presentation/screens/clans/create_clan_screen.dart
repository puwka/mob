import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../presentation/providers/clan_providers.dart';
import '../../../presentation/providers/profile_providers.dart';
import '../../../presentation/providers/repository_providers.dart';
import '../../../services/level_service.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_text_field.dart';
import '../../../widgets/city_select_field.dart';
import '../../../widgets/feedback.dart';

class CreateClanScreen extends ConsumerStatefulWidget {
  const CreateClanScreen({super.key});

  @override
  ConsumerState<CreateClanScreen> createState() => _CreateClanScreenState();
}

class _CreateClanScreenState extends ConsumerState<CreateClanScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _tag = TextEditingController();
  final _city = TextEditingController();
  final _description = TextEditingController();
  Uint8List? _avatarBytes;
  var _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _city.text.trim().isNotEmpty) return;
      final profileCity =
          ref.read(currentProfileProvider).valueOrNull?.city.trim();
      if (profileCity != null && profileCity.isNotEmpty) {
        setState(() => _city.text = profileCity);
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _tag.dispose();
    _city.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _avatarBytes = bytes);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);

    final level = ref.read(levelProgressProvider).currentLevel;
    if (level < LevelService.minLevelToCreateClan) {
      setState(() {
        _error =
            'Создать клан можно с ${LevelService.minLevelToCreateClan} уровня (сейчас $level)';
      });
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final repo = ref.read(clanRepositoryProvider);
      final storage = ref.read(clanAvatarStorageServiceProvider);
      final uid = ref.read(supabaseClientProvider).auth.currentUser?.id;

      final clanId = await repo.createClan(
        name: _name.text.trim(),
        tag: _tag.text.trim().toUpperCase(),
        description: _description.text.trim(),
        city: _city.text.trim(),
      );

      if (_avatarBytes != null && uid != null) {
        final url = await storage.uploadClanAvatar(
          clanId: clanId,
          userId: uid,
          bytes: _avatarBytes!,
        );
        await repo.setClanAvatarUrl(clanId: clanId, avatarUrl: url);
      }

      await ref.read(myClanProvider.notifier).refresh(silent: true);
      if (!mounted) return;
      context.go('/main/profile/clan/$clanId');
    } catch (e) {
      setState(() => _error = ErrorMapper.map(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final level = ref.watch(levelProgressProvider).currentLevel;
    final canCreate = level >= LevelService.minLevelToCreateClan;

    return Scaffold(
      appBar: AppBar(title: const Text('Создать клан')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (!canCreate) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    'Создание клана доступно с ${LevelService.minLevelToCreateClan} уровня. '
                    'Ваш уровень: $level.',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13.5,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Center(
                child: GestureDetector(
                  onTap: _loading || !canCreate ? null : _pickAvatar,
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.accentDim),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _avatarBytes == null
                        ? const Icon(
                            Icons.add_a_photo_outlined,
                            color: AppColors.textTertiary,
                          )
                        : Image.memory(_avatarBytes!, fit: BoxFit.cover),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text(
                  'Эмблема клана',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _name,
                label: 'Название',
                hint: 'Феникс',
                textInputAction: TextInputAction.next,
                enabled: canCreate && !_loading,
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.length < 2) return 'Минимум 2 символа';
                  if (t.length > 40) return 'Максимум 40 символов';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _tag,
                label: 'TAG',
                hint: 'PHX',
                textInputAction: TextInputAction.next,
                enabled: canCreate && !_loading,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'[a-zA-Z0-9а-яА-ЯёЁ]'),
                  ),
                  LengthLimitingTextInputFormatter(6),
                  _UpperCaseFormatter(),
                ],
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.length < 2) return '2–6 символов';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              CitySelectField(
                controller: _city,
                label: 'Местоположение',
                enabled: canCreate && !_loading,
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _description,
                label: 'Описание',
                hint: 'О клане, стиле игры',
                maxLines: 4,
                minLines: 3,
                enabled: canCreate && !_loading,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                ErrorBanner(message: _error!),
              ],
              const SizedBox(height: 18),
              AppButton(
                label: canCreate
                    ? 'Создать клан'
                    : 'Нужен ${LevelService.minLevelToCreateClan} уровень',
                loading: _loading,
                onPressed: _loading || !canCreate ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
