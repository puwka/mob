import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/conversation.dart';
import 'auth_providers.dart';
import 'chat_providers.dart';
import 'clan_providers.dart';
import 'dating_providers.dart';
import 'market_providers.dart';
import 'organizer_events_providers.dart';
import 'organizer_wallet_providers.dart';
import 'offline_qr_providers.dart';
import 'polygon_providers.dart';
import 'profile_providers.dart';
import 'progression_providers.dart';

/// Clears caches that belong to the signed-in user.
/// Call after login / register / logout so data cannot leak across accounts.
void resetUserScopedProviders(Ref ref) {
  // Drop cached auth/user first so dependents rebuild with the live session.
  ref.invalidate(authStateProvider);
  ref.invalidate(currentUserProvider);
  ref.invalidate(currentProfileProvider);
  ref.invalidate(myClanProvider);
  ref.invalidate(folderUnreadProvider);
  ref.invalidate(conversationsByTypeProvider);
  ref.invalidate(conversationDetailProvider);
  ref.invalidate(chatMessagesProvider);
  ref.invalidate(datingFeedProvider);
  ref.invalidate(datingMatchesProvider);
  ref.invalidate(myPolygonsProvider);
  ref.invalidate(userEventsCountProvider);
  ref.invalidate(achievementsProvider);
  ref.invalidate(myProfilePhotosProvider);
  ref.invalidate(myListingsProvider);
  ref.invalidate(organizerWalletProvider);
  ref.invalidate(organizerTransactionsProvider);
  ref.invalidate(organizerDashboardProvider);
  ref.invalidate(organizerWithdrawalsProvider);
  ref.invalidate(myOrganizerEventsProvider);
  ref.invalidate(offlineQrStoreProvider);
  ref.read(pendingAttendanceTickProvider.notifier).state = 0;

  ref.read(previousLevelProvider.notifier).state = null;
  ref.read(progressionFeedbackProvider.notifier).state = null;
  ref.read(chatFolderProvider.notifier).state = ConversationType.user;
  ref.read(datingCityFilterProvider.notifier).state = null;
}
