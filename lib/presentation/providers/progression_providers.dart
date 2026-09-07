import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/user_achievement_progress.dart';
import '../../services/progression_service.dart';
import 'auth_providers.dart';
import 'profile_providers.dart';
import 'repository_providers.dart';

/// Transient UI feedback after participation changes.
class ProgressionFeedback {
  const ProgressionFeedback({
    this.newLevel,
    this.unlockedAchievements = const [],
  });

  final int? newLevel;
  final List<UserAchievementProgress> unlockedAchievements;

  bool get hasContent =>
      newLevel != null || unlockedAchievements.isNotEmpty;
}

final progressionFeedbackProvider =
    StateProvider<ProgressionFeedback?>((ref) => null);

/// Rebuilds XP / level / achievements from Supabase after event changes.
final progressionControllerProvider =
    AsyncNotifierProvider<ProgressionController, ProgressionSnapshot?>(
  ProgressionController.new,
);

class ProgressionController extends AsyncNotifier<ProgressionSnapshot?> {
  @override
  Future<ProgressionSnapshot?> build() async => null;

  /// Call only after a successful join/leave write to Supabase.
  Future<ProgressionSnapshot> refreshAfterEventChange() async {
    final profile = ref.read(currentProfileProvider).valueOrNull;
    if (profile == null) {
      throw StateError('Profile is required for progression refresh');
    }

    final previousLevel = ref.read(levelProgressProvider).currentLevel;

    // Re-read participation count from Supabase (source of truth).
    final eventsCount =
        await ref.read(userEventsCountProvider.notifier).refresh();

    final sync = await ref.read(achievementRepositoryProvider).syncForProfile(
          userId: profile.id,
          profile: profile,
          eventsCount: eventsCount,
        );

    ref.read(achievementsProvider.notifier).setItems(sync.items);

    // Soft-refresh profile row (keeps UI coherent without loading flash).
    await ref.read(currentProfileProvider.notifier).refresh(silent: true);

    final latestProfile =
        ref.read(currentProfileProvider).valueOrNull ?? profile;

    final snapshot = ref.read(progressionServiceProvider).buildSnapshot(
          profile: latestProfile,
          eventsCount: eventsCount,
          achievements: sync.items,
          newlyUnlocked: sync.newlyUnlocked,
          previousLevel: previousLevel,
        );

    state = AsyncData(snapshot);

    if (snapshot.leveledUp || snapshot.newlyUnlocked.isNotEmpty) {
      ref.read(progressionFeedbackProvider.notifier).state =
          ProgressionFeedback(
        newLevel: snapshot.leveledUp ? snapshot.level.currentLevel : null,
        unlockedAchievements: snapshot.newlyUnlocked,
      );
    }

    return snapshot;
  }
}
