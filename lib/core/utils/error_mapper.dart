import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_exception.dart';

/// Maps low-level errors to user-facing Russian messages.
abstract final class ErrorMapper {
  static String map(Object error) {
    if (error is AppException) return error.message;

    if (error is SocketException ||
        error.toString().contains('SocketException') ||
        error.toString().contains('Failed host lookup') ||
        error.toString().contains('Network is unreachable')) {
      return 'Нет подключения к интернету. Проверьте сеть и попробуйте снова.';
    }

    if (error is AuthException) {
      return _auth(error);
    }

    if (error is PostgrestException) {
      return _postgrest(error);
    }

    if (error is AuthRetryableFetchException) {
      return 'Нет подключения к интернету. Проверьте сеть и попробуйте снова.';
    }

    final message = error.toString().toLowerCase();
    if (message.contains('network') ||
        message.contains('connection') ||
        message.contains('timed out') ||
        message.contains('timeout')) {
      return 'Нет подключения к интернету. Проверьте сеть и попробуйте снова.';
    }

    return 'Что-то пошло не так. Попробуйте позже.';
  }

  static String _auth(AuthException e) {
    final msg = e.message.toLowerCase();
    final code = e.code?.toLowerCase() ?? '';

    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid credentials') ||
        code == 'invalid_credentials') {
      return 'Неверный телефон или пароль';
    }
    if (msg.contains('user already registered') ||
        msg.contains('already been registered') ||
        code == 'user_already_exists') {
      return 'Пользователь с таким телефоном уже зарегистрирован';
    }
    if (msg.contains('email address') && msg.contains('invalid')) {
      return 'Некорректный формат телефона';
    }
    if (msg.contains('password') &&
        (msg.contains('weak') || msg.contains('at least'))) {
      return 'Пароль слишком короткий. Минимум 8 символов';
    }
    if (msg.contains('rate limit') || code.contains('over_request')) {
      return 'Слишком много попыток. Подождите немного.';
    }
    if (msg.contains('network') || msg.contains('fetch')) {
      return 'Нет подключения к интернету. Проверьте сеть и попробуйте снова.';
    }

    return e.message.isNotEmpty
        ? e.message
        : 'Ошибка авторизации. Попробуйте снова.';
  }

  static String _postgrest(PostgrestException e) {
    final blob = '${e.message} ${e.details ?? ''} ${e.hint ?? ''}'.toUpperCase();
    if (blob.contains('NO_SLOTS')) {
      return 'Мест нет';
    }
    if (e.code == '23505') {
      if (e.message.contains('nickname') ||
          (e.details?.toString().contains('nickname') ?? false)) {
        return 'Этот никнейм уже занят';
      }
      if (e.message.contains('phone') ||
          (e.details?.toString().contains('phone') ?? false)) {
        return 'Пользователь с таким телефоном уже зарегистрирован';
      }
      if (blob.contains('EVENT_PARTICIPANTS')) {
        return 'Вы уже записаны на это мероприятие';
      }
      return 'Такие данные уже используются';
    }
    if (e.code == '42P17' || blob.contains('INFINITE RECURSION')) {
      return 'Ошибка доступа к диалогам. Обновите SQL-миграции.';
    }
    return 'Ошибка сервера. Попробуйте позже.';
  }
}
