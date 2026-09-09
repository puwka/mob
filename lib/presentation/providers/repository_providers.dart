import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/achievement_repository.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/cities_repository.dart';
import '../../data/repositories/clan_repository.dart';
import '../../data/repositories/dating_repository.dart';
import '../../data/repositories/event_repository.dart';
import '../../data/repositories/listing_repository.dart';
import '../../data/repositories/polygon_repository.dart';
import '../../data/repositories/profile_photo_repository.dart';
import '../../data/repositories/ranking_repository.dart';
import '../../services/achievement_service.dart';
import '../../services/avatar_storage_service.dart';
import '../../services/chat_image_storage_service.dart';
import '../../services/chat_voice_storage_service.dart';
import '../../services/clan_avatar_storage_service.dart';
import '../../services/event_image_storage_service.dart';
import '../../services/level_service.dart';
import '../../services/listing_image_storage_service.dart';
import '../../services/progression_service.dart';
import 'auth_providers.dart';

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  return EventRepository(ref.watch(supabaseClientProvider));
});

final listingRepositoryProvider = Provider<ListingRepository>((ref) {
  return ListingRepository(ref.watch(supabaseClientProvider));
});

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(ref.watch(supabaseClientProvider));
});

final clanRepositoryProvider = Provider<ClanRepository>((ref) {
  return ClanRepository(ref.watch(supabaseClientProvider));
});

final datingRepositoryProvider = Provider<DatingRepository>((ref) {
  return DatingRepository(ref.watch(supabaseClientProvider));
});

final rankingRepositoryProvider = Provider<RankingRepository>((ref) {
  return RankingRepository(ref.watch(supabaseClientProvider));
});

final citiesRepositoryProvider = Provider<CitiesRepository>((ref) {
  return CitiesRepository(ref.watch(supabaseClientProvider));
});

final polygonRepositoryProvider = Provider<PolygonRepository>((ref) {
  return PolygonRepository(ref.watch(supabaseClientProvider));
});

final clanAvatarStorageServiceProvider =
    Provider<ClanAvatarStorageService>((ref) {
  return ClanAvatarStorageService(ref.watch(supabaseClientProvider));
});

final eventImageStorageServiceProvider =
    Provider<EventImageStorageService>((ref) {
  return EventImageStorageService(ref.watch(supabaseClientProvider));
});

final listingImageStorageServiceProvider =
    Provider<ListingImageStorageService>((ref) {
  return ListingImageStorageService(ref.watch(supabaseClientProvider));
});

final chatVoiceStorageServiceProvider = Provider<ChatVoiceStorageService>((ref) {
  return ChatVoiceStorageService(ref.watch(supabaseClientProvider));
});

final chatImageStorageServiceProvider = Provider<ChatImageStorageService>((ref) {
  return ChatImageStorageService(ref.watch(supabaseClientProvider));
});

final achievementServiceProvider = Provider<AchievementService>((ref) {
  return const AchievementService();
});

final achievementRepositoryProvider = Provider<AchievementRepository>((ref) {
  return AchievementRepository(
    client: ref.watch(supabaseClientProvider),
    service: ref.watch(achievementServiceProvider),
  );
});

final levelServiceProvider = Provider<LevelService>((ref) {
  return const LevelService();
});

final xpServiceProvider = Provider<XpService>((ref) {
  return ref.watch(levelServiceProvider).xpService;
});

final progressionServiceProvider = Provider<ProgressionService>((ref) {
  return ProgressionService(levelService: ref.watch(levelServiceProvider));
});

final avatarStorageServiceProvider = Provider<AvatarStorageService>((ref) {
  return AvatarStorageService(ref.watch(supabaseClientProvider));
});

final profilePhotoRepositoryProvider = Provider<ProfilePhotoRepository>((ref) {
  return ProfilePhotoRepository(ref.watch(supabaseClientProvider));
});
