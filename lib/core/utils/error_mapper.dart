import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_exception.dart';

/// Maps low-level errors to user-facing Russian messages.
abstract final class ErrorMapper {
  static bool isNetwork(Object error) {
    if (error is SocketException) return true;
    if (error is AuthRetryableFetchException) return true;
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('connection refused') ||
        text.contains('connection reset') ||
        text.contains('clientexception') ||
        text.contains('network') ||
        text.contains('connection') ||
        text.contains('timed out') ||
        text.contains('timeout') ||
        text.contains('нет подключения');
  }

  static String map(Object error) {
    if (error is AppException) {
      if (isNetwork(error.message)) {
        return 'Нет подключения к интернету. Проверьте сеть и попробуйте снова.';
      }
      return error.message;
    }

    if (isNetwork(error)) {
      return 'Нет подключения к интернету. Проверьте сеть и попробуйте снова.';
    }

    if (error is AuthException) {
      return _auth(error);
    }

    if (error is PostgrestException) {
      return _postgrest(error);
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
    if (blob.contains('USER_BLOCKED')) {
      return 'Пользователь недоступен';
    }
    if (blob.contains('CHAT_MUTED')) {
      return 'Вам запрещено писать в этот чат (мут)';
    }
    if (blob.contains('MAP_LOCATION_REQUIRED')) {
      return 'Укажите точку на карте или выберите полигон';
    }
    if (blob.contains('INVALID_COORDINATES')) {
      return 'Некорректные координаты';
    }
    if (blob.contains('INVALID_ADDRESS') || blob.contains('INVALID_POLYGON_NAME')) {
      return 'Проверьте название и адрес полигона';
    }
    if (blob.contains('CANNOT_ACTION_SELF')) {
      return 'Нельзя выполнить действие на себя';
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
    if (blob.contains('NOT ASSIGNED') || blob.contains('V_MATCH')) {
      return 'Ошибка знакомств на сервере. Примените миграцию 000043.';
    }
    // Surface actionable server messages (P0001 custom exceptions).
    final msg = e.message.trim();
    if (msg.isNotEmpty && msg.length < 180 && !msg.toLowerCase().contains('json')) {
      return msg;
    }
    return 'Ошибка сервера. Попробуйте позже.';
  }
}
