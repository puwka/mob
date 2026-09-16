import 'package:intl/intl.dart';

/// Telegram-style date labels for chats / dialogs (ru).
abstract final class ChatDateFormat {
  static bool sameDay(DateTime a, DateTime b) {
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }

  static DateTime _dateOnly(DateTime dt) {
    final l = dt.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  /// Sticky / in-chat day separator: «Сегодня», «Вчера», «12 сентября».
  static String daySeparator(DateTime dt, {DateTime? now}) {
    final local = dt.toLocal();
    final today = _dateOnly(now ?? DateTime.now());
    final day = _dateOnly(local);
    final diff = today.difference(day).inDays;

    if (diff == 0) return 'Сегодня';
    if (diff == 1) return 'Вчера';
    if (local.year == today.year) {
      return DateFormat('d MMMM', 'ru').format(local);
    }
    return DateFormat('d MMMM yyyy', 'ru').format(local);
  }

  /// Dialog list timestamp: today → time; yesterday → «вчера»;
  /// last 7 days → weekday; else short date.
  static String dialogList(DateTime dt, {DateTime? now}) {
    final local = dt.toLocal();
    final today = _dateOnly(now ?? DateTime.now());
    final day = _dateOnly(local);
    final diff = today.difference(day).inDays;

    if (diff == 0) return DateFormat('HH:mm').format(local);
    if (diff == 1) return 'вчера';
    if (diff > 1 && diff < 7) {
      return DateFormat('EEE', 'ru').format(local);
    }
    if (local.year == today.year) {
      return DateFormat('dd.MM', 'ru').format(local);
    }
    return DateFormat('dd.MM.yy', 'ru').format(local);
  }

  static String messageTime(DateTime dt) =>
      DateFormat('HH:mm').format(dt.toLocal());
}
