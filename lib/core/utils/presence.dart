class Presence {
  Presence._();

  /// Consider user online if last heartbeat was within this window.
  static const onlineWindow = Duration(minutes: 3);

  static bool isOnline(DateTime? lastSeenAt, {DateTime? now}) {
    if (lastSeenAt == null) return false;
    final t = now ?? DateTime.now();
    return t.difference(lastSeenAt.toLocal()) <= onlineWindow;
  }

  static String labelRu(DateTime? lastSeenAt, {DateTime? now}) {
    return isOnline(lastSeenAt, now: now) ? 'онлайн' : 'не в сети';
  }
}
