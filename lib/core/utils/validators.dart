import 'phone_utils.dart';

abstract final class Validators {
  static final RegExp _nickname = RegExp(r'^[a-zA-Z0-9_а-яА-ЯёЁ\-]+$');

  static String? phone(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Укажите номер телефона';
    if (!PhoneUtils.isValidRuMobile(v)) {
      return 'Некорректный формат телефона';
    }
    return null;
  }

  static String? nickname(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Укажите никнейм';
    if (v.length < 3 || v.length > 20) {
      return 'Никнейм: от 3 до 20 символов';
    }
    if (!_nickname.hasMatch(v)) {
      return 'Допустимы буквы, цифры, _ и -';
    }
    return null;
  }

  static String? city(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Выберите город';
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Укажите пароль';
    if (v.length < 8) return 'Минимум 8 символов';
    return null;
  }

  static String? confirmPassword(String? value, String password) {
    final v = value ?? '';
    if (v.isEmpty) return 'Подтвердите пароль';
    if (v != password) return 'Пароли не совпадают';
    return null;
  }
}
