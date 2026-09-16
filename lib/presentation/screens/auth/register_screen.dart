import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/legal_docs.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../core/utils/validators.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_text_field.dart';
import '../../../widgets/city_select_field.dart';
import '../../../widgets/feedback.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController(text: '+7');
  final _nickname = TextEditingController();
  final _city = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _checkingNick = false;
  bool _acceptedAgreements = false;
  String? _nicknameRemoteError;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _phone.selection = TextSelection.collapsed(offset: _phone.text.length);
  }

  @override
  void dispose() {
    _phone.dispose();
    _nickname.dispose();
    _city.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<bool> _ensureNicknameUnique() async {
    final local = Validators.nickname(_nickname.text);
    if (local != null) {
      setState(() => _nicknameRemoteError = null);
      return false;
    }

    setState(() {
      _checkingNick = true;
      _nicknameRemoteError = null;
    });

    try {
      final available = await ref
          .read(profileRepositoryProvider)
          .isNicknameAvailable(_nickname.text);
      if (!available) {
        setState(() => _nicknameRemoteError = 'Этот никнейм уже занят');
        return false;
      }
      return true;
    } catch (e) {
      setState(() => _formError = ErrorMapper.map(e));
      return false;
    } finally {
      if (mounted) setState(() => _checkingNick = false);
    }
  }

  void _openLegalDoc({required String title, required String body}) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (context) {
        final height = MediaQuery.sizeOf(context).height * 0.78;
        return SizedBox(
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
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Закрыть',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    child: Text(
                      body.trim(),
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _formError = null;
      _nicknameRemoteError = null;
    });

    if (!_formKey.currentState!.validate()) return;

    if (!_acceptedAgreements) {
      setState(
        () => _formError =
            'Нужно принять пользовательское соглашение и политику конфиденциальности',
      );
      return;
    }

    final nickOk = await _ensureNicknameUnique();
    if (!nickOk || !mounted) return;

    await ref.read(authControllerProvider.notifier).register(
          phone: _phone.text,
          nickname: _nickname.text,
          city: _city.text,
          password: _password.text,
        );

    if (!mounted) return;

    final state = ref.read(authControllerProvider);
    if (state.hasError) {
      setState(() => _formError = ErrorMapper.map(state.error!));
      return;
    }

    context.go('/main/profile');
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final loading = authState.isLoading || _checkingNick;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: loading ? null : () => context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Регистрация',
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            fontSize: 24,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Создайте профиль бойца и начните путь в тактических играх.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    AppTextField(
                      controller: _phone,
                      label: 'Телефон',
                      hint: '+7 (___) ___-__-__',
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      prefixIcon: Icons.phone_outlined,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      validator: Validators.phone,
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _nickname,
                      label: 'Никнейм / позывной',
                      hint: '3–20 символов',
                      textInputAction: TextInputAction.next,
                      prefixIcon: Icons.alternate_email,
                      autofillHints: const [AutofillHints.username],
                      validator: (v) =>
                          Validators.nickname(v) ?? _nicknameRemoteError,
                      onChanged: (_) {
                        if (_nicknameRemoteError != null) {
                          setState(() => _nicknameRemoteError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    CitySelectField(
                      controller: _city,
                      enabled: !loading,
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _password,
                      label: 'Пароль',
                      hint: 'Минимум 8 символов',
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.next,
                      prefixIcon: Icons.lock_outline,
                      autofillHints: const [AutofillHints.newPassword],
                      validator: Validators.password,
                      suffix: IconButton(
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _confirm,
                      label: 'Подтверждение пароля',
                      hint: 'Повторите пароль',
                      obscureText: _obscureConfirm,
                      textInputAction: TextInputAction.done,
                      prefixIcon: Icons.lock_outline,
                      validator: (v) =>
                          Validators.confirmPassword(v, _password.text),
                      suffix: IconButton(
                        onPressed: () => setState(
                          () => _obscureConfirm = !_obscureConfirm,
                        ),
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: _acceptedAgreements,
                            activeColor: AppColors.accent,
                            side: const BorderSide(color: AppColors.border),
                            onChanged: loading
                                ? null
                                : (v) => setState(() {
                                      _acceptedAgreements = v ?? false;
                                      if (_acceptedAgreements &&
                                          _formError != null) {
                                        _formError = null;
                                      }
                                    }),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'Я принимаю ',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(height: 1.35),
                                ),
                                GestureDetector(
                                  onTap: loading
                                      ? null
                                      : () => _openLegalDoc(
                                            title: LegalDocs.termsTitle,
                                            body: LegalDocs.termsBody,
                                          ),
                                  child: Text(
                                    'пользовательское соглашение',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: AppColors.accent,
                                          fontWeight: FontWeight.w600,
                                          decoration: TextDecoration.underline,
                                          decorationColor: AppColors.accent,
                                          height: 1.35,
                                        ),
                                  ),
                                ),
                                Text(
                                  ' и ',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(height: 1.35),
                                ),
                                GestureDetector(
                                  onTap: loading
                                      ? null
                                      : () => _openLegalDoc(
                                            title: LegalDocs.privacyTitle,
                                            body: LegalDocs.privacyBody,
                                          ),
                                  child: Text(
                                    'политику конфиденциальности',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: AppColors.accent,
                                          fontWeight: FontWeight.w600,
                                          decoration: TextDecoration.underline,
                                          decorationColor: AppColors.accent,
                                          height: 1.35,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_formError != null) ...[
                      const SizedBox(height: 12),
                      ErrorBanner(message: _formError!),
                    ],
                    const SizedBox(height: 20),
                    AppButton(
                      label: 'Создать аккаунт',
                      loading: loading,
                      onPressed: loading ? null : _submit,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Уже есть аккаунт?',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        TextButton(
                          onPressed:
                              loading ? null : () => context.go('/login'),
                          child: const Text('Войти'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
