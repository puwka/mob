import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/conversation.dart';
import '../../presentation/providers/auth_providers.dart';
import '../../presentation/screens/auth/login_screen.dart';
import '../../presentation/screens/auth/register_screen.dart';
import '../../presentation/screens/chats/chat_screen.dart';
import '../../presentation/screens/chats/dialogs_screen.dart';
import '../../presentation/screens/clans/clan_profile_screen.dart';
import '../../presentation/screens/clans/clan_search_screen.dart';
import '../../presentation/screens/clans/create_clan_screen.dart';
import '../../presentation/screens/events/event_details_screen.dart';
import '../../presentation/screens/events/events_screen.dart';
import '../../presentation/screens/main/main_screen.dart';
import '../../presentation/screens/market/create_listing_screen.dart';
import '../../presentation/screens/market/listing_details_screen.dart';
import '../../presentation/screens/market/market_screen.dart';
import '../../presentation/screens/market/my_listings_screen.dart';
import '../../presentation/screens/organizer/create_event_screen.dart';
import '../../presentation/screens/organizer/event_qr_scanner_screen.dart';
import '../../presentation/screens/organizer/my_organizer_events_screen.dart';
import '../../presentation/screens/organizer/organizer_balance_screen.dart';
import '../../presentation/screens/organizer/organizer_event_details_screen.dart';
import '../../presentation/screens/organizer/organizer_hub_screen.dart';
import '../../presentation/screens/organizer/organizer_scanner_pick_screen.dart';
import '../../presentation/screens/profile/achievements_screen.dart';
import '../../presentation/screens/profile/edit_profile_screen.dart';
import '../../presentation/screens/profile/my_qr_screen.dart';
import '../../presentation/screens/profile/profile_photos_screen.dart';
import '../../presentation/screens/profile/profile_screen.dart';
import '../../presentation/screens/rating/ranking_screen.dart';
import '../../presentation/screens/rating/user_profile_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final goRouterProvider = Provider<GoRouter>((ref) {
  final authListenable = _AuthRefreshListenable(ref);

  ref.onDispose(authListenable.dispose);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/login',
    refreshListenable: authListenable,
    redirect: (context, state) {
      final auth = ref.read(authRepositoryProvider);
      final loggedIn = auth.isAuthenticated;
      final loc = state.matchedLocation;
      final isAuthRoute = loc == '/login' || loc == '/register';

      if (!loggedIn && !isAuthRoute) return '/login';
      if (loggedIn && isAuthRoute) return '/main/profile';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainScreen(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/main/games',
                builder: (context, state) => const EventsScreen(),
                routes: [
                  GoRoute(
                    path: ':eventId',
                    builder: (context, state) => EventDetailsScreen(
                      eventId: state.pathParameters['eventId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/main/market',
                builder: (context, state) => const MarketScreen(),
                routes: [
                  GoRoute(
                    path: 'create',
                    builder: (context, state) => const CreateListingScreen(),
                  ),
                  GoRoute(
                    path: 'my',
                    builder: (context, state) => const MyListingsScreen(),
                  ),
                  GoRoute(
                    path: ':listingId',
                    builder: (context, state) => ListingDetailsScreen(
                      listingId: state.pathParameters['listingId']!,
                    ),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        builder: (context, state) => CreateListingScreen(
                          listingId: state.pathParameters['listingId'],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/main/chats',
                builder: (context, state) => const DialogsScreen(),
                routes: [
                  GoRoute(
                    path: 'folder/:folder',
                    builder: (context, state) {
                      final folder = state.pathParameters['folder'];
                      final type = switch (folder) {
                        'clan' => ConversationType.clan,
                        _ => ConversationType.market,
                      };
                      return ChatFolderScreen(type: type);
                    },
                  ),
                  GoRoute(
                    path: ':conversationId',
                    builder: (context, state) => ChatScreen(
                      conversationId:
                          state.pathParameters['conversationId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/main/profile',
                builder: (context, state) => const ProfileScreen(),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (context, state) => const EditProfileScreen(),
                  ),
                  GoRoute(
                    path: 'achievements',
                    builder: (context, state) => const AchievementsScreen(),
                  ),
                  GoRoute(
                    path: 'rating',
                    builder: (context, state) => const RankingScreen(),
                    routes: [
                      GoRoute(
                        path: 'user/:userId',
                        builder: (context, state) => UserProfileScreen(
                          userId: state.pathParameters['userId']!,
                        ),
                      ),
                      GoRoute(
                        path: 'clan/:clanId',
                        builder: (context, state) => ClanProfileScreen(
                          clanId: state.pathParameters['clanId']!,
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'user/:userId',
                    builder: (context, state) => UserProfileScreen(
                      userId: state.pathParameters['userId']!,
                    ),
                  ),
                  GoRoute(
                    path: 'photos',
                    builder: (context, state) => const ProfilePhotosScreen(),
                  ),
                  GoRoute(
                    path: 'qr',
                    builder: (context, state) => const MyQrScreen(),
                  ),
                  GoRoute(
                    path: 'organizer',
                    redirect: (context, state) {
                      final isOrg = ref
                              .read(currentProfileProvider)
                              .valueOrNull
                              ?.isOrganizer ??
                          false;
                      if (!isOrg) return '/main/profile';
                      return null;
                    },
                    builder: (context, state) => const OrganizerHubScreen(),
                    routes: [
                      GoRoute(
                        path: 'events',
                        builder: (context, state) =>
                            const MyOrganizerEventsScreen(),
                        routes: [
                          GoRoute(
                            path: 'create',
                            builder: (context, state) =>
                                const CreateEventScreen(),
                          ),
                          GoRoute(
                            path: ':eventId',
                            builder: (context, state) =>
                                OrganizerEventDetailsScreen(
                              eventId: state.pathParameters['eventId']!,
                            ),
                            routes: [
                              GoRoute(
                                path: 'participants',
                                builder: (context, state) =>
                                    EventParticipantsScreen(
                                  eventId: state.pathParameters['eventId']!,
                                ),
                              ),
                              GoRoute(
                                path: 'scanner',
                                builder: (context, state) =>
                                    EventQrScannerScreen(
                                  eventId: state.pathParameters['eventId']!,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'scanner',
                        builder: (context, state) =>
                            const OrganizerScannerPickScreen(),
                      ),
                      GoRoute(
                        path: 'balance',
                        builder: (context, state) =>
                            const OrganizerBalanceScreen(),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'clans',
                    builder: (context, state) => const ClanSearchScreen(),
                  ),
                  GoRoute(
                    path: 'clan/create',
                    builder: (context, state) => const CreateClanScreen(),
                  ),
                  GoRoute(
                    path: 'clan/:clanId',
                    builder: (context, state) => ClanProfileScreen(
                      clanId: state.pathParameters['clanId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Bridges Riverpod auth stream → GoRouter refresh.
class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(this._ref) {
    _sub = _ref.listen(authStateProvider, (previous, next) => notifyListeners());
  }

  final Ref _ref;
  late final ProviderSubscription<AsyncValue<dynamic>> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}
