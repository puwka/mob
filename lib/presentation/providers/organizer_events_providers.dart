import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/event.dart';
import 'repository_providers.dart';

final myOrganizerEventsProvider =
    AsyncNotifierProvider<MyOrganizerEventsNotifier, List<Event>>(
  MyOrganizerEventsNotifier.new,
);

class MyOrganizerEventsNotifier extends AsyncNotifier<List<Event>> {
  @override
  Future<List<Event>> build() {
    return ref.read(eventRepositoryProvider).fetchMyOrganizerEvents();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(eventRepositoryProvider).fetchMyOrganizerEvents(),
    );
  }
}

final eventParticipantsProvider =
    FutureProvider.family<List<EventParticipant>, String>((ref, eventId) {
  return ref.watch(eventRepositoryProvider).fetchParticipants(eventId);
});
