import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_exception.dart';
import '../../domain/models/conversation.dart';
import '../../domain/models/profile.dart';
import '../../domain/models/profile_photo.dart';
import '../../domain/models/user_achievement_progress.dart';
import '../../services/level_service.dart';
import 'auth_providers.dart';
import 'chat_providers.dart';
import 'repository_providers.dart';

final profilePhotosProvider =
    FutureProvider.family<List<ProfilePhoto>, String>((ref, userId) {
  return ref.watch(profilePhotoRepositoryProvider).fetchForUser(userId);
});

final myProfilePhotosProvider = FutureProvider<List<ProfilePhoto>>((ref) {
  final uid = ref.watch(currentUserProvider)?.id;
  if (uid == null) return Future.value(const []);
  return ref.watch(profilePhotoRepositoryProvider).fetchForUser(uid);
});

final profileByIdProvider =
    FutureProvider.family<Profile?, String>((ref, userId) {
  return ref.watch(profileRepositoryProvider).getByIdOrNull(userId);
});

/// Level bar for any profile (same formula as own passport).
final levelProgressForProfileProvider =
    Provider.family<LevelProgress, Profile>((ref, profile) {
  final events =
      ref.watch(userEventsCountByIdProvider(profile.id)).valueOrNull ?? 0;
  return ref.watch(levelServiceProvider).calculateFromProfile(
        profile,
        eventsCount: events,
      );
});

/// Achievements preview for any user (read-only evaluate).
final userAchievementsByIdProvider = FutureProvider.family<
    List<UserAchievementProgress>, String>((ref, userId) async {
  final profile = await ref.watch(profileByIdProvider(userId).future);
  if (profile == null) return const [];
  final events =
      await ref.watch(userEventsCountByIdProvider(userId).future);
  return ref.read(achievementRepositoryProvider).loadProgress(
        profile: profile,
        eventsCount: events,
      );
});

/// Event participations for any user (XP formula).
final userEventsCountByIdProvider =
    FutureProvider.family<int, String>((ref, userId) {
  return ref.watch(eventRepositoryProvider).getUserEventsCount(userId);
});

/// Live XP for a profile (same formula as ranking / level bar).
final profileXpProvider = Provider.family<int, Profile>((ref, profile) {
  final events =
      ref.watch(userEventsCountByIdProvider(profile.id)).valueOrNull ?? 0;
  return ref.watch(xpServiceProvider).calculateFromProfile(
        profile,
        eventsCount: events,
      );
});

/// Live count of `event_participants` rows for the current user.
final userEventsCountProvider =
    AsyncNotifierProvider<UserEventsCountNotifier, int>(
  UserEventsCountNotifier.new,
);

class UserEventsCountNotifier extends AsyncNotifier<int> {
  @override
  Future<int> build() async {
    final user = ref.watch(currentUserProvider);
    if (user == null) return 0;
    return ref.read(eventRepositoryProvider).getUserEventsCount(user.id);
  }

  Future<int> refresh() async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      state = const AsyncData(0);
      return 0;
    }
    final count =
        await ref.read(eventRepositoryProvider).getUserEventsCount(user.id);
    state = AsyncData(count);
    return count;
  }
}

final levelProgressProvider = Provider<LevelProgress>((ref) {
  final profile = ref.watch(currentProfileProvider).valueOrNull;
  final eventsCount = ref.watch(userEventsCountProvider).valueOrNull ?? 0;
  final levelService = ref.watch(levelServiceProvider);
  if (profile == null) {
    return levelService.calculateLevel(0);
  }
  return levelService.calculateFromProfile(
    profile,
    eventsCount: eventsCount,
  );
});

/// Last known level used to detect level-ups.
final previousLevelProvider = StateProvider<int?>((ref) => null);

final achievementsProvider =
    AsyncNotifierProvider<AchievementsNotifier, List<UserAchievementProgress>>(
  AchievementsNotifier.new,
);

class AchievementsNotifier
    extends AsyncNotifier<List<UserAchievementProgress>> {
  @override
  Future<List<UserAchievementProgress>> build() async {
    final profile = await ref.watch(currentProfileProvider.future);
    if (profile == null) return const [];
    final eventsCount = await ref.watch(userEventsCountProvider.future);
    return _sync(profile, eventsCount);
  }

  Future<List<UserAchievementProgress>> _sync(
    Profile profile,
    int eventsCount,
  ) async {
    final result =
        await ref.read(achievementRepositoryProvider).syncForProfile(
              userId: profile.id,
              profile: profile,
              eventsCount: eventsCount,
            );
    return result.items;
  }

  void setItems(List<UserAchievementProgress> items) {
    state = AsyncData(items);
  }

  Future<void> refresh() async {
    final profile = ref.read(currentProfileProvider).valueOrNull;
    if (profile == null) {
      state = const AsyncData([]);
      return;
    }
    final eventsCount =
        await ref.read(userEventsCountProvider.notifier).refresh();
    state = await AsyncValue.guard(() => _sync(profile, eventsCount));
  }
}

class ProfileController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> updateProfile({
    String? nickname,
    String? city,
    String? bio,
    bool clearBio = false,
    String? avatarUrl,
    bool clearAvatarUrl = false,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final current = ref.read(currentProfileProvider).valueOrNull;
      if (current == null) return;

      if (nickname != null &&
          nickname.trim().toLowerCase() != current.nickname.toLowerCase()) {
        final available = await ref
            .read(profileRepositoryProvider)
            .isNicknameAvailable(nickname, excludingUserId: current.id);
        if (!available) {
          throw const AppException('Этот никнейм уже занят');
        }
      }

      final updated = await ref.read(profileRepositoryProvider).updateFields(
            id: current.id,
            nickname: nickname,
            city: city,
            bio: bio,
            clearBio: clearBio,
            avatarUrl: avatarUrl,
            clearAvatarUrl: clearAvatarUrl,
          );

      ref.read(currentProfileProvider.notifier).setProfile(updated);
      await ref.read(achievementsProvider.notifier).refresh();
      if (city != null) {
        ref.invalidate(conversationsByTypeProvider(ConversationType.city));
        unawaited(
          ref.read(folderUnreadProvider.notifier).refresh(silent: true),
        );
      }
    });
  }

  Future<void> uploadAvatar(Uint8List bytes, String contentType) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final current = ref.read(currentProfileProvider).valueOrNull;
      if (current == null) return;

      final url = await ref.read(avatarStorageServiceProvider).uploadAvatar(
            userId: current.id,
            bytes: bytes,
            contentType: contentType,
          );

      final updated = await ref.read(profileRepositoryProvider).updateFields(
            id: current.id,
            avatarUrl: url,
          );

      ref.read(currentProfileProvider.notifier).setProfile(updated);
    });
  }

  Future<void> removeAvatar() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final current = ref.read(currentProfileProvider).valueOrNull;
      if (current == null) return;

      await ref.read(avatarStorageServiceProvider).deleteAvatar(current.id);
      final updated = await ref.read(profileRepositoryProvider).updateFields(
            id: current.id,
            clearAvatarUrl: true,
          );
      ref.read(currentProfileProvider.notifier).setProfile(updated);
    });
  }
}

final profileControllerProvider =
    AsyncNotifierProvider<ProfileController, void>(ProfileController.new);
