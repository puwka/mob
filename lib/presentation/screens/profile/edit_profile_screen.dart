import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../core/utils/validators.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../presentation/providers/profile_providers.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_text_field.dart';
import '../../../widgets/city_picker.dart';
import '../../../widgets/feedback.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nickname;
  late final TextEditingController _city;
  late final TextEditingController _bio;
  String? _error;
  bool _initialized = false;

  @override
  void dispose() {
    if (_initialized) {
      _nickname.dispose();
      _city.dispose();
      _bio.dispose();
    }
    super.dispose();
  }

  void _ensureControllers(String nickname, String city, String? bio) {
    if (_initialized) return;
    _nickname = TextEditingController(text: nickname);
    _city = TextEditingController(text: city);
    _bio = TextEditingController(text: bio ?? '');
    _initialized = true;
  }

  Future<void> _pickCity() async {
    final city = await showCityPicker(context, selected: _city.text);
    if (city != null) setState(() => _city.text = city);
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (file == null) return;

    final bytes = await file.readAsBytes();
    final mime = file.mimeType ?? _mimeFromName(file.name);

    await ref.read(profileControllerProvider.notifier).uploadAvatar(bytes, mime);
    final state = ref.read(profileControllerProvider);
    if (!mounted) return;
    if (state.hasError) {
      setState(() => _error = ErrorMapper.map(state.error!));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Аватар обновлён')),
      );
    }
  }

  Future<void> _removeAvatar() async {
    await ref.read(profileControllerProvider.notifier).removeAvatar();
    final state = ref.read(profileControllerProvider);
    if (!mounted) return;
    if (state.hasError) {
      setState(() => _error = ErrorMapper.map(state.error!));
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    final bio = _bio.text.trim();
    await ref.read(profileControllerProvider.notifier).updateProfile(
          nickname: _nickname.text.trim(),
          city: _city.text.trim(),
          bio: bio,
          clearBio: bio.isEmpty,
        );

    final state = ref.read(profileControllerProvider);
    if (!mounted) return;
    if (state.hasError) {
      setState(() => _error = ErrorMapper.map(state.error!));
      return;
    }

    Navigator.of(context).pop();
  }

  String _mimeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final saving = ref.watch(profileControllerProvider).isLoading;

    if (profile == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    _ensureControllers(profile.nickname, profile.city, profile.bio);

    return Scaffold(
      appBar: AppBar(title: const Text('Редактирование')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Column(
                    children: [
                      _EditAvatar(
                        nickname: profile.nickname,
                        url: profile.avatarUrl,
                        onTap: saving ? null : _pickAvatar,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: saving ? null : _pickAvatar,
                            child: const Text('Загрузить'),
                          ),
                          if (profile.avatarUrl != null &&
                              profile.avatarUrl!.isNotEmpty)
                            TextButton(
                              onPressed: saving ? null : _removeAvatar,
                              child: const Text('Удалить'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _nickname,
                  label: 'Никнейм / позывной',
                  validator: Validators.nickname,
                  enabled: !saving,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _city,
                  label: 'Город',
                  readOnly: true,
                  validator: Validators.city,
                  onTap: saving ? null : _pickCity,
                  suffix: const Icon(
                    Icons.expand_more,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _bio,
                  label: 'О себе',
                  hint: 'Кратко о себе, роли, команде…',
                  enabled: !saving,
                  maxLines: 5,
                  minLines: 3,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  ErrorBanner(message: _error!),
                ],
                const SizedBox(height: 28),
                AppButton(
                  label: 'Сохранить',
                  loading: saving,
                  onPressed: saving ? null : _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EditAvatar extends StatelessWidget {
  const _EditAvatar({
    required this.nickname,
    this.url,
    this.onTap,
  });

  final String nickname;
  final String? url;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final letter = nickname.isNotEmpty ? nickname[0].toUpperCase() : '?';

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surfaceElevated,
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.5),
                width: 2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: url != null && url!.isNotEmpty
                ? Image.network(
                    url!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Text(
                        letter,
                        style: Theme.of(context)
                            .textTheme
                            .headlineLarge
                            ?.copyWith(color: AppColors.accent),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      letter,
                      style:
                          Theme.of(context).textTheme.headlineLarge?.copyWith(
                                color: AppColors.accent,
                              ),
                    ),
                  ),
          ),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.background, width: 2),
            ),
            child: const Icon(Icons.photo_camera, size: 16, color: Colors.black),
          ),
        ],
      ),
    );
  }
}
