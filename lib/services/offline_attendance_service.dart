import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/utils/app_exception.dart';
import '../core/utils/error_mapper.dart';
import '../data/repositories/event_repository.dart';
import '../domain/models/event.dart';
import 'offline_qr_store.dart';

/// Offline-first attendance confirm for polygon days without network.
class OfflineAttendanceService {
  OfflineAttendanceService({
    required EventRepository events,
    required OfflineQrStore store,
  })  : _events = events,
        _store = store;

  final EventRepository _events;
  final OfflineQrStore _store;

  OfflineQrStore get store => _store;

  /// Prefetch roster while online so scanning works on the field.
  /// Returns cached roster; [fromNetwork] is true when freshly downloaded.
  Future<({OfflineEventRoster? roster, bool fromNetwork})> prefetchRoster({
    required String eventId,
    required String eventTitle,
  }) async {
    try {
      final participants = await _events.fetchParticipants(eventId);
      await _store.saveEventRoster(
        eventId: eventId,
        eventTitle: eventTitle,
        participants: participants,
      );
      return (
        roster: _store.loadEventRoster(eventId),
        fromNetwork: true,
      );
    } catch (e) {
      debugPrint('offline roster prefetch failed: $e');
      return (
        roster: _store.loadEventRoster(eventId),
        fromNetwork: false,
      );
    }
  }

  OfflineEventRoster? cachedRoster(String eventId) =>
      _store.loadEventRoster(eventId);

  /// Try online confirm; on network failure confirm against local roster.
  Future<AttendanceConfirmResult> confirm({
    required String eventId,
    required String publicQrId,
    String? eventTitleHint,
  }) async {
    try {
      final result = await _events
          .confirmAttendance(eventId: eventId, publicQrId: publicQrId)
          .timeout(const Duration(seconds: 8));
      await _markLocalConfirmed(
        eventId: eventId,
        publicQrId: publicQrId,
        eventTitle: result.eventTitle,
        attendedAt: result.attendedAt,
      );
      return result;
    } catch (e) {
      if (!_isNetworkFailure(e)) {
        // Still useful: if already confirmed server-side, mirror locally.
        final msg = ErrorMapper.map(e).toUpperCase();
        if (msg.contains('УЖЕ ПОДТВЕРЖД') ||
            '$e'.toUpperCase().contains('ALREADY_CONFIRMED')) {
          await _markLocalConfirmed(
            eventId: eventId,
            publicQrId: publicQrId,
            eventTitle: eventTitleHint,
            attendedAt: DateTime.now(),
          );
        }
        throw AppException(ErrorMapper.map(e));
      }
      return _confirmOffline(
        eventId: eventId,
        publicQrId: publicQrId,
        eventTitleHint: eventTitleHint,
      );
    }
  }

  Future<AttendanceConfirmResult> _confirmOffline({
    required String eventId,
    required String publicQrId,
    String? eventTitleHint,
  }) async {
    final roster = _store.loadEventRoster(eventId);
    if (roster == null || roster.participants.isEmpty) {
      throw const AppException(
        'Нет локального списка участников. Откройте сканер при интернете '
        'перед выездом на полигон.',
      );
    }

    final pending = _store.loadPendingScans().any(
          (s) => s.eventId == eventId && s.publicQrId == publicQrId,
        );
    final participant = roster.findByPublicQrId(publicQrId);
    if (participant == null) {
      throw const AppException(
        'Пользователь не зарегистрирован на это мероприятие '
        '(по локальному списку).',
      );
    }
    if (participant.isConfirmed || pending) {
      throw const AppException('Присутствие уже подтверждено');
    }

    final scannedAt = DateTime.now();
    final scan = PendingAttendanceScan(
      id: '${eventId}_${publicQrId}_$scannedAt',
      eventId: eventId,
      eventTitle: roster.eventTitle.isNotEmpty
          ? roster.eventTitle
          : (eventTitleHint ?? 'Мероприятие'),
      publicQrId: publicQrId,
      userId: participant.userId,
      nickname: participant.nickname ?? 'Боец',
      city: participant.city ?? '',
      scannedAt: scannedAt,
      avatarUrl: participant.avatarUrl,
    );
    await _store.enqueuePending(scan);
    await _markLocalConfirmed(
      eventId: eventId,
      publicQrId: publicQrId,
      eventTitle: scan.eventTitle,
      attendedAt: scannedAt,
    );

    return AttendanceConfirmResult(
      userId: scan.userId,
      nickname: scan.nickname,
      city: scan.city,
      eventId: scan.eventId,
      eventTitle: scan.eventTitle,
      attendedAt: scannedAt,
      avatarUrl: scan.avatarUrl,
      pendingSync: true,
    );
  }

  Future<void> _markLocalConfirmed({
    required String eventId,
    required String publicQrId,
    required DateTime attendedAt,
    String? eventTitle,
  }) async {
    final roster = _store.loadEventRoster(eventId);
    if (roster == null) return;
    final updated = [
      for (final p in roster.participants)
        if ((p.publicQrId ?? '').toLowerCase() == publicQrId.toLowerCase())
          p.copyWith(
            attendanceStatus: AttendanceStatus.confirmed,
            attendedAt: attendedAt,
          )
        else
          p,
    ];
    await _store.saveEventRoster(
      eventId: eventId,
      eventTitle: eventTitle ?? roster.eventTitle,
      participants: updated,
    );
  }

  /// Push queued offline confirms when the network is back.
  Future<int> syncPending() async {
    final pending = _store.loadPendingScans();
    if (pending.isEmpty) return 0;

    var synced = 0;
    for (final scan in pending) {
      try {
        await _events
            .confirmAttendance(
              eventId: scan.eventId,
              publicQrId: scan.publicQrId,
            )
            .timeout(const Duration(seconds: 10));
        await _store.removePending(scan.id);
        synced++;
      } catch (e) {
        final blob = '${ErrorMapper.map(e)} $e'.toUpperCase();
        if (blob.contains('ALREADY_CONFIRMED') ||
            blob.contains('УЖЕ ПОДТВЕРЖД')) {
          await _store.removePending(scan.id);
          synced++;
          continue;
        }
        if (_isNetworkFailure(e)) {
          // Stop early — still offline.
          break;
        }
        // Permanent local mismatch (not registered etc.) — drop to avoid loop.
        await _store.removePending(scan.id);
      }
    }
    return synced;
  }

  int pendingCount() => _store.loadPendingScans().length;

  bool _isNetworkFailure(Object e) {
    if (ErrorMapper.isNetwork(e)) return true;
    if (e is AppException && ErrorMapper.isNetwork(e.message)) return true;
    return false;
  }
}
