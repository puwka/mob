import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../domain/models/conversation.dart';
import '../../../domain/models/dating.dart';
import '../../../presentation/providers/chat_providers.dart';
import '../../../presentation/providers/dating_providers.dart';
import '../../../presentation/providers/repository_providers.dart';
import '../dating/dating_match_dialog.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen>
    with WidgetsBindingObserver {
  bool _showingAlert = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pendingDatingNotificationsProvider.notifier).refresh(silent: true);
    });
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted || _showingAlert) return;
      ref.read(pendingDatingNotificationsProvider.notifier).refresh(silent: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(pendingDatingNotificationsProvider.notifier).refresh(silent: true);
    }
  }

  Future<void> _consumePending() async {
    if (_showingAlert || !mounted) return;
    final pending =
        ref.read(pendingDatingNotificationsProvider).valueOrNull;
    if (pending == null || pending.isEmpty) return;

    final notification = pending.first;
    _showingAlert = true;
    try {
      await ref
          .read(pendingDatingNotificationsProvider.notifier)
          .markSeen(notification.notificationId);
      if (!mounted) return;

      if (notification.isMatch) {
        final result = await showDatingMatchDialog(
          context,
          me: notification.me,
          other: notification.other,
          conversationId: notification.conversationId,
        );
        if (!mounted) return;
        if (result == DatingMatchDialogResult.write &&
            notification.conversationId != null) {
          ref.read(chatFolderProvider.notifier).state = ConversationType.dating;
          context.push('/main/chats/${notification.conversationId}');
        }
      } else {
        final likedBack = await _showIncomingLikeDialog(notification);
        if (!mounted) return;
        if (likedBack) {
          try {
            final result =
                await ref.read(datingRepositoryProvider).processAction(
                      targetUserId: notification.other.id,
                      action: DatingActionType.like,
                    );
            ref.invalidate(datingFeedProvider);
            ref.invalidate(datingMatchesProvider);
            ref.invalidate(pendingDatingNotificationsProvider);
            if (!mounted) return;
            if (result.matched) {
              final matchResult = await showDatingMatchDialog(
                context,
                me: result.me,
                other: result.target,
                conversationId: result.conversationId,
              );
              if (!mounted) return;
              if (matchResult == DatingMatchDialogResult.write &&
                  result.conversationId != null) {
                ref.read(chatFolderProvider.notifier).state =
                    ConversationType.dating;
                context.push('/main/chats/${result.conversationId}');
              }
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Лайк отправлен')),
              );
            }
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(ErrorMapper.map(e))),
            );
          }
        }
      }
    } finally {
      _showingAlert = false;
      if (mounted) {
        // Show next pending alert if any.
        WidgetsBinding.instance.addPostFrameCallback((_) => _consumePending());
      }
    }
  }

  Future<bool> _showIncomingLikeDialog(DatingNotification n) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Вам поставили лайк'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: AppColors.surfaceElevated,
              backgroundImage: (n.other.avatarUrl != null &&
                      n.other.avatarUrl!.isNotEmpty)
                  ? NetworkImage(n.other.avatarUrl!)
                  : null,
              child: (n.other.avatarUrl == null || n.other.avatarUrl!.isEmpty)
                  ? const Icon(Icons.person_outline)
                  : null,
            ),
            const SizedBox(height: 12),
            Text(
              n.other.nickname,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
            if (n.other.city.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                n.other.city,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 10),
            const Text(
              'Лайкните в ответ, чтобы получить совпадение.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Позже'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Нравится'),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _onTap(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
    ref.read(pendingDatingNotificationsProvider.notifier).refresh(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.navigationShell.currentIndex;

    ref.listen(pendingDatingNotificationsProvider, (prev, next) {
      final list = next.valueOrNull;
      if (list == null || list.isEmpty || _showingAlert) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _consumePending());
    });

    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.borderSubtle)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                _NavItem(
                  icon: Icons.sports_esports_outlined,
                  activeIcon: Icons.sports_esports,
                  label: 'Игры',
                  selected: index == 0,
                  onTap: () => _onTap(0),
                ),
                _NavItem(
                  icon: Icons.shopping_cart_outlined,
                  activeIcon: Icons.shopping_cart,
                  label: 'Барахолка',
                  selected: index == 1,
                  onTap: () => _onTap(1),
                ),
                _NavItem(
                  icon: Icons.chat_bubble_outline,
                  activeIcon: Icons.chat_bubble,
                  label: 'Диалоги',
                  selected: index == 2,
                  onTap: () => _onTap(2),
                ),
                _NavItem(
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                  label: 'Профиль',
                  selected: index == 3,
                  onTap: () => _onTap(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.navInactive;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? activeIcon : icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
