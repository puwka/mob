import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/event.dart';
import '../../services/offline_qr_store.dart';
import 'auth_providers.dart';
import 'offline_qr_providers.dart';
import 'repository_providers.dart';

final myOrganizerEventsProvider =
    AsyncNotifierProvider<MyOrganizerEventsNotifier, List<Event>>(
  MyOrganizerEventsNotifier.new,
);

class MyOrganizerEventsNotifier extends AsyncNotifier<List<Event>> {
  @override
  Future<List<Event>> build() {
    return _load();
  }

  Future<List<Event>> _load() async {
    final uid = ref.read(currentUserProvider)?.id;
    final store = await OfflineQrStore.open();
    try {
      final events =
          await ref.read(eventRepositoryProvider).fetchMyOrganizerEvents();
      if (uid != null) {
        await store.saveOrganizerEvents(organizerId: uid, events: events);
      }
      final offline = ref.read(offlineAttendanceServiceProvider);
      if (offline != null) {
        for (final e in events.where((e) => e.status == EventStatus.active)) {
          unawaited(
            offline.prefetchRoster(eventId: e.id, eventTitle: e.title),
          );
        }
      }
      return events;
    } catch (_) {
      if (uid != null) {
        final cached = store.loadOrganizerEvents(uid);
        if (cached.isNotEmpty) return cached;
      }
      rethrow;
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }
}

final eventParticipantsProvider =
    FutureProvider.family<List<EventParticipant>, String>((ref, eventId) async {
  final repo = ref.watch(eventRepositoryProvider);
  final offline = ref.watch(offlineAttendanceServiceProvider);
  try {
    final list = await repo.fetchParticipants(eventId);
    final title = offline?.cachedRoster(eventId)?.eventTitle ?? 'Мероприятие';
    await offline?.store.saveEventRoster(
      eventId: eventId,
      eventTitle: title,
      participants: list,
    );
    return list;
  } catch (_) {
    final cached = offline?.cachedRoster(eventId)?.participants;
    if (cached != null && cached.isNotEmpty) return cached;
    rethrow;
  }
});
