import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../core/utils/validators.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_text_field.dart';

/// Login UI aligned with register / rest of app. Auth logic unchanged.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _phoneFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _obscure = true;
  String? _formError;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _phoneFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _formError = null);
    if (!_formKey.currentState!.validate()) return;

    await ref.read(authControllerProvider.notifier).login(
          phone: _phone.text,
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
    final loading = ref.watch(authControllerProvider).isLoading;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Вход',
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            fontSize: 24,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Войдите, чтобы продолжить',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 22),
                    AppTextField(
                      controller: _phone,
                      focusNode: _phoneFocus,
                      label: 'Телефон',
                      hint: 'Номер телефона',
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      prefixIcon: Icons.phone_outlined,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      validator: Validators.phone,
                      enabled: !loading,
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _password,
                      focusNode: _passwordFocus,
                      label: 'Пароль',
                      hint: 'Пароль',
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      prefixIcon: Icons.lock_outline,
                      autofillHints: const [AutofillHints.password],
                      validator: Validators.password,
                      enabled: !loading,
                      suffix: IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: loading
                            ? null
                            : () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 18,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                    if (_formError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _formError!,
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontSize: 12.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    AppButton(
                      label: 'Войти',
                      loading: loading,
                      onPressed: loading ? null : _submit,
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: GestureDetector(
                        onTap: loading
                            ? null
                            : () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Восстановление пароля пока недоступно',
                                    ),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                        child: Text(
                          'Забыли пароль?',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.accent.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Нет аккаунта? ',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontSize: 13,
                              ),
                        ),
                        GestureDetector(
                          onTap: loading ? null : () => context.go('/register'),
                          child: const Text(
                            'Зарегистрироваться',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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
