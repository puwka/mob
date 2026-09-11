import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_providers.dart';
import 'repository_providers.dart';

final conversationNotificationsMutedProvider =
    FutureProvider.family<bool, String>((ref, conversationId) async {
  ref.watch(authStateProvider);
  return ref
      .read(notificationRepositoryProvider)
      .isConversationMuted(conversationId);
});
