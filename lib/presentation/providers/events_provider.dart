import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/event_cities.dart';
import '../../domain/models/event.dart';
import 'auth_providers.dart';
import 'profile_providers.dart';
import 'progression_providers.dart';
import 'repository_providers.dart';

final eventCityFilterProvider = StateProvider<String>((ref) => EventCities.all);

final eventsListProvider =
    AsyncNotifierProvider<EventsListNotifier, List<Event>>(
  EventsListNotifier.new,
);

class EventsListNotifier extends AsyncNotifier<List<Event>> {
  RealtimeChannel? _channel;
  Timer? _debounce;

  @override
  Future<List<Event>> build() async {
    final city = ref.watch(eventCityFilterProvider);
    ref.onDispose(() {
      _debounce?.cancel();
      final channel = _channel;
      _channel = null;
      if (channel != null) {
        unawaited(ref.read(supabaseClientProvider).removeChannel(channel));
      }
    });

    final events = await _fetch(city);

    _channel ??= ref.read(eventRepositoryProvider).subscribeParticipants(
          channelName: 'events-list-participants',
          onChange: _onRealtime,
        );

    return events;
  }

  Future<List<Event>> _fetch(String cityFilter) {
    final city = cityFilter == EventCities.all ? null : cityFilter;
    return ref.read(eventRepositoryProvider).fetchEvents(city: city);
  }

  void _onRealtime() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      refresh(silent: true);
    });
  }

  Future<void> refresh({bool silent = false}) async {
    final city = ref.read(eventCityFilterProvider);
    if (!silent) {
      state = const AsyncLoading();
    }
    state = await AsyncValue.guard(() => _fetch(city));
  }
}

final eventDetailsProvider =
    AsyncNotifierProvider.family<EventDetailsNotifier, Event, String>(
  EventDetailsNotifier.new,
);

class EventDetailsNotifier extends FamilyAsyncNotifier<Event, String> {
  RealtimeChannel? _channel;
  Timer? _debounce;

  @override
  Future<Event> build(String arg) async {
    ref.onDispose(() {
      _debounce?.cancel();
      final channel = _channel;
      _channel = null;
      if (channel != null) {
        unawaited(ref.read(supabaseClientProvider).removeChannel(channel));
      }
    });

    final event = await ref.read(eventRepositoryProvider).fetchById(arg);

    _channel ??= ref.read(eventRepositoryProvider).subscribeParticipants(
          channelName: 'event-detail-$arg',
          onChange: () {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 350), () {
              refresh(silent: true);
            });
          },
        );

    return event;
  }

  Future<void> refresh({bool silent = false}) async {
    if (!silent) state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(eventRepositoryProvider).fetchById(arg),
    );
  }

  Future<void> join() async {
    // 1) Persist participation first — UI updates only after success.
    final updated = await ref.read(eventRepositoryProvider).join(arg);
    state = AsyncData(updated);
    await ref.read(eventsListProvider.notifier).refresh(silent: true);

    // 2) Recalculate XP / level / achievements from live counts.
    try {
      await ref
          .read(progressionControllerProvider.notifier)
          .refreshAfterEventChange();
    } catch (_) {
      // Participation is already saved; keep UI truthful and retry counts.
      await ref.read(userEventsCountProvider.notifier).refresh();
    }
  }

  Future<void> leave() async {
    final updated = await ref.read(eventRepositoryProvider).leave(arg);
    state = AsyncData(updated);
    await ref.read(eventsListProvider.notifier).refresh(silent: true);
    try {
      await ref
          .read(progressionControllerProvider.notifier)
          .refreshAfterEventChange();
    } catch (_) {
      await ref.read(userEventsCountProvider.notifier).refresh();
    }
  }
}
