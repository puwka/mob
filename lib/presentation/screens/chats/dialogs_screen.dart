import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_layout.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/chat_date_format.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../core/utils/presence.dart';
import '../../../domain/models/conversation.dart';
import '../../../domain/models/profile.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../presentation/providers/chat_providers.dart';
import '../../../presentation/providers/clan_providers.dart';
import '../../../presentation/providers/repository_providers.dart';
import '../../../widgets/app_page_body.dart';
import '../../../widgets/feedback.dart';
import '../../../widgets/presence_status.dart';

class DialogsScreen extends ConsumerWidget {
  const DialogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadMap =
        ref.watch(folderUnreadProvider).valueOrNull ?? const {};
    final myClan = ref.watch(myClanProvider).valueOrNull;
    final personalAsync =
        ref.watch(conversationsByTypeProvider(ConversationType.user));
    final cityChat = ref
        .watch(conversationsByTypeProvider(ConversationType.city))
        .valueOrNull
        ?.firstOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppLayout.pageGutter(context),
                10,
                AppLayout.pageGutter(context) - 4,
                8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Диалоги',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontSize: 18,
                          ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Поддержка',
                    icon: const Icon(Icons.support_agent_outlined),
                    color: AppColors.textSecondary,
                    onPressed: () => _openSupport(context, ref),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AppPageBody(
                child: personalAsync.when(
                loading: () => const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (e, _) => Center(
                  child: AsyncErrorRetry(
                    message: ErrorMapper.map(e),
                    onRetry: () => ref
                        .read(
                          conversationsByTypeProvider(ConversationType.user)
                              .notifier,
                        )
                        .refresh(),
                  ),
                ),
                data: (items) {
                  return RefreshIndicator(
                    color: AppColors.accent,
                    onRefresh: () async {
                      await ref
                          .read(
                            conversationsByTypeProvider(ConversationType.user)
                                .notifier,
                          )
                          .refresh();
                      try {
                        await ref.read(chatRepositoryProvider).openCityChat();
                      } catch (_) {}
                      await ref
                          .read(
                            conversationsByTypeProvider(ConversationType.city)
                                .notifier,
                          )
                          .refresh(silent: true);
                      await ref
                          .read(folderUnreadProvider.notifier)
                          .refresh(silent: true);
                      await ref.read(myClanProvider.notifier).refresh(
                            silent: true,
                          );
                    },
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: AppLayout.pagePadding(context, bottom: 16),
                      children: [
                        _FolderTile(
                          title: ConversationType.market.folderLabel,
                          subtitle: _folderSubtitle(
                            unread: unreadMap[ConversationType.market] ?? 0,
                            emptyHint: 'Товары и обмены',
                          ),
                          meta: 'Папка',
                          icon: Icons.storefront_outlined,
                          unread: unreadMap[ConversationType.market] ?? 0,
                          onTap: () =>
                              context.go('/main/chats/folder/market'),
                        ),
                        const SizedBox(height: 6),
                        _FolderTile(
                          title: ConversationType.dating.folderLabel,
                          subtitle: _folderSubtitle(
                            unread: unreadMap[ConversationType.dating] ?? 0,
                            emptyHint: 'Чаты после совпадений',
                          ),
                          meta: 'Папка',
                          icon: Icons.groups_outlined,
                          unread: unreadMap[ConversationType.dating] ?? 0,
                          onTap: () =>
                              context.go('/main/chats/folder/dating'),
                        ),
                        const SizedBox(height: 6),
                        _FolderTile(
                          title: ConversationType.event.folderLabel,
                          subtitle: _folderSubtitle(
                            unread: unreadMap[ConversationType.event] ?? 0,
                            emptyHint: 'Чаты ваших игр',
                          ),
                          meta: 'Папка',
                          icon: Icons.event_outlined,
                          unread: unreadMap[ConversationType.event] ?? 0,
                          onTap: () =>
                              context.go('/main/chats/folder/event'),
                        ),
                        const SizedBox(height: 6),
                        _FolderTile(
                          title: ConversationType.clan.folderLabel,
                          subtitle: myClan?.name ??
                              _folderSubtitle(
                                unread: unreadMap[ConversationType.clan] ?? 0,
                                emptyHint: 'Чаты команды',
                              ),
                          meta: 'Папка',
                          icon: Icons.shield_outlined,
                          avatarUrl: myClan?.avatarUrl,
                          unread: unreadMap[ConversationType.clan] ?? 0,
                          onTap: () => context.go('/main/chats/folder/clan'),
                        ),
                        if (cityChat != null) ...[
                          const SizedBox(height: 6),
                          _DialogTile(
                            item: cityChat,
                            leadingOverride: _cityChatIcon(),
                            onTap: () =>
                                context.go('/main/chats/${cityChat.id}'),
                          ),
                        ],
                        const SizedBox(height: 6),
                        if (items.isEmpty) ...[
                          const SizedBox(height: 24),
                          const EmptyStateCard(
                            title: 'Нет личных диалогов',
                            subtitle:
                                'Напишите пользователю из профиля или объявления.',
                            icon: Icons.chat_bubble_outline,
                          ),
                        ] else ...[
                          for (var i = 0; i < items.length; i++) ...[
                            if (i > 0) const SizedBox(height: 6),
                            _DialogTile(
                              item: items[i],
                              onTap: () =>
                                  context.go('/main/chats/${items[i].id}'),
                              onConfirmDelete: () => _confirmHideDialog(
                                context,
                                ref,
                                items[i],
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  );
                },
              ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _folderSubtitle({required int unread, required String emptyHint}) {
    if (unread > 0) {
      return unread == 1
          ? '1 непрочитанное'
          : '$unread непрочитанных';
    }
    return emptyHint;
  }
}

Future<void> _openSupport(BuildContext context, WidgetRef ref) async {
  final role = ref.read(currentProfileProvider).valueOrNull?.badgeRole;
  final isStaff = role == ProfileBadgeRole.admin;
  if (isStaff) {
    if (!context.mounted) return;
    context.go('/main/chats/folder/support');
    return;
  }

  try {
    final id = await ref.read(chatRepositoryProvider).openSupportChat();
    if (!context.mounted) return;
    if (id == null || id.isEmpty) {
      // Staff inbox empty, or role mismatch on server — show folder.
      context.go('/main/chats/folder/support');
      return;
    }
    ref.invalidate(conversationsByTypeProvider(ConversationType.support));
    unawaited(ref.read(folderUnreadProvider.notifier).refresh(silent: true));
    context.go('/main/chats/$id');
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ErrorMapper.map(e))),
    );
  }
}

class ChatFolderScreen extends ConsumerStatefulWidget {
  const ChatFolderScreen({super.key, required this.type});

  final ConversationType type;

  @override
  ConsumerState<ChatFolderScreen> createState() => _ChatFolderScreenState();
}

class _ChatFolderScreenState extends ConsumerState<ChatFolderScreen> {
  var _openingSupport = false;

  ConversationType get type => widget.type;

  @override
  void initState() {
    super.initState();
    if (type == ConversationType.support) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeAutoOpenSupport();
      });
    }
  }

  Future<void> _maybeAutoOpenSupport() async {
    if (!mounted || _openingSupport) return;
    final role = ref.read(currentProfileProvider).valueOrNull?.badgeRole;
    if (role == ProfileBadgeRole.admin) return;

    final items =
        ref.read(conversationsByTypeProvider(ConversationType.support)).valueOrNull;
    if (items != null && items.isNotEmpty) {
      // Regular user already has a ticket — open it.
      context.go('/main/chats/${items.first.id}');
      return;
    }

    setState(() => _openingSupport = true);
    try {
      final id = await ref.read(chatRepositoryProvider).openSupportChat();
      if (!mounted) return;
      if (id == null || id.isEmpty) {
        setState(() => _openingSupport = false);
        return;
      }
      ref.invalidate(conversationsByTypeProvider(ConversationType.support));
      unawaited(ref.read(folderUnreadProvider.notifier).refresh(silent: true));
      context.go('/main/chats/$id');
    } catch (e) {
      if (!mounted) return;
      setState(() => _openingSupport = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorMapper.map(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(conversationsByTypeProvider(type));
    final myClan = type == ConversationType.clan
        ? ref.watch(myClanProvider).valueOrNull
        : null;
    final myCity = type == ConversationType.city
        ? ref.watch(currentProfileProvider).valueOrNull?.city.trim()
        : null;
    final isAdmin = ref.watch(currentProfileProvider).valueOrNull?.badgeRole ==
        ProfileBadgeRole.admin;
    final showSupportCta =
        type == ConversationType.support && !isAdmin;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(
          type == ConversationType.clan && myClan != null
              ? myClan.name
              : type == ConversationType.city &&
                      myCity != null &&
                      myCity.isNotEmpty
                  ? myCity
                  : type.folderLabel,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/main/chats'),
        ),
        actions: [
          if (showSupportCta)
            IconButton(
              tooltip: 'Написать в поддержку',
              icon: _openingSupport
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.support_agent_outlined),
              onPressed: _openingSupport
                  ? null
                  : () => _openSupport(context, ref),
            ),
        ],
      ),
      body: AppPageBody(
        child: async.when(
        loading: () => const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        error: (e, _) => Center(
          child: AsyncErrorRetry(
            message: ErrorMapper.map(e),
            onRetry: () =>
                ref.read(conversationsByTypeProvider(type).notifier).refresh(),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            if (showSupportCta && _openingSupport) {
              return const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.all(AppLayout.pageGutter(context)),
              children: [
                const SizedBox(height: 40),
                EmptyStateCard(
                  title: 'Нет диалогов',
                  subtitle: type == ConversationType.market
                      ? 'Нажмите «Написать» на объявлении.'
                      : type == ConversationType.dating
                          ? 'Совпадения из дружбы появятся здесь.'
                          : type == ConversationType.city
                              ? 'Укажите город в профиле — чат откроется автоматически.'
                              : type == ConversationType.event
                                  ? 'Создайте игру или нажмите «Участвовать» — чат появится здесь.'
                                  : type == ConversationType.support
                                      ? (isAdmin
                                          ? 'Обращения пользователей появятся здесь.'
                                          : 'Нажмите кнопку ниже, чтобы написать в поддержку.')
                                      : 'Вступите в команду, чтобы открыть чаты.',
                  icon: type == ConversationType.support
                      ? Icons.support_agent_outlined
                      : Icons.chat_bubble_outline,
                ),
                if (showSupportCta) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _openingSupport
                        ? null
                        : () => _openSupport(context, ref),
                    icon: const Icon(Icons.support_agent_outlined),
                    label: const Text('Написать в поддержку'),
                  ),
                ],
              ],
            );
          }

          return RefreshIndicator(
            color: AppColors.accent,
            onRefresh: () =>
                ref.read(conversationsByTypeProvider(type).notifier).refresh(),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AppLayout.pagePadding(context, bottom: 16),
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final item = items[index];
                return _DialogTile(
                  item: item,
                  onTap: () => context.go('/main/chats/${item.id}'),
                  leadingOverride: type == ConversationType.clan
                      ? _clanChannelIcon(item)
                      : type == ConversationType.city
                          ? _cityChatIcon()
                          : type == ConversationType.event
                              ? _eventChatIcon()
                              : null,
                  onConfirmDelete: (type == ConversationType.market ||
                          type == ConversationType.dating)
                      ? () => _confirmHideDialog(context, ref, item)
                      : null,
                );
              },
            ),
          );
        },
      ),
      ),
    );
  }

  Widget _clanChannelIcon(ConversationPreview item) {
    final officers = item.clanChannel == ClanChatChannel.officers;
    return CircleAvatar(
      radius: 22,
      backgroundColor: AppColors.surfaceElevated,
      child: Icon(
        officers ? Icons.military_tech_outlined : Icons.groups_outlined,
        color: AppColors.accent,
        size: 22,
      ),
    );
  }
}

Widget _cityChatIcon() {
  return const CircleAvatar(
    radius: 22,
    backgroundColor: AppColors.surfaceElevated,
    child: Icon(
      Icons.location_city_outlined,
      color: AppColors.accent,
      size: 22,
    ),
  );
}

Widget _eventChatIcon() {
  return const CircleAvatar(
    radius: 22,
    backgroundColor: AppColors.surfaceElevated,
    child: Icon(
      Icons.event_outlined,
      color: AppColors.accent,
      size: 22,
    ),
  );
}

Future<bool> _confirmHideDialog(
  BuildContext context,
  WidgetRef ref,
  ConversationPreview item,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Удалить диалог?'),
      content: const Text(
        'Диалог исчезнет из списка. История сохранится — '
        'чат появится снова, если кто-то напишет.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Удалить'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  try {
    await ref.read(chatRepositoryProvider).hideConversation(item.id);
    ref.invalidate(conversationsByTypeProvider(item.type));
    ref.invalidate(folderUnreadProvider);
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorMapper.map(e))),
      );
    }
    return false;
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.icon,
    required this.onTap,
    this.avatarUrl,
    this.unread = 0,
  });

  final String title;
  final String subtitle;
  final String meta;
  final IconData icon;
  final String? avatarUrl;
  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(
              color: unread > 0
                  ? AppColors.accent.withValues(alpha: 0.55)
                  : AppColors.border,
            ),
            color: unread > 0
                ? AppColors.accentSoft.withValues(alpha: 0.35)
                : null,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.surfaceElevated,
                backgroundImage: avatarUrl != null && avatarUrl!.isNotEmpty
                    ? NetworkImage(avatarUrl!)
                    : null,
                child: avatarUrl == null || avatarUrl!.isEmpty
                    ? Icon(icon, color: AppColors.accent, size: 22)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontSize: 14.5,
                                  fontWeight: unread > 0
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                ),
                          ),
                        ),
                        Text(
                          meta,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  fontSize: 12.5,
                                  color: AppColors.textSecondary,
                                ),
                          ),
                        ),
                        if (unread > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            constraints: const BoxConstraints(minWidth: 18),
                            height: 18,
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text(
                              unread > 99 ? '99+' : '$unread',
                              style: const TextStyle(
                                color: Color(0xFF0A0B0D),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textTertiary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogTile extends StatelessWidget {
  const _DialogTile({
    required this.item,
    required this.onTap,
    this.leadingOverride,
    this.onConfirmDelete,
  });

  final ConversationPreview item;
  final VoidCallback onTap;
  final Widget? leadingOverride;
  final Future<bool> Function()? onConfirmDelete;

  @override
  Widget build(BuildContext context) {
    final time = item.lastMessageAt ?? item.updatedAt;
    final timeLabel = _formatTime(time);
    final letter = item.displayTitle.isNotEmpty
        ? item.displayTitle[0].toUpperCase()
        : '?';
    final showPresence = item.type == ConversationType.user ||
        item.type == ConversationType.dating ||
        (item.type == ConversationType.market && item.peerUserId != null);
    final online = Presence.isOnline(item.peerLastSeenAt);

    final tile = Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(
              color: item.hasUnread
                  ? AppColors.accent.withValues(alpha: 0.55)
                  : AppColors.border,
            ),
            color: item.hasUnread
                ? AppColors.accentSoft.withValues(alpha: 0.35)
                : null,
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  leadingOverride ??
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: AppColors.surfaceElevated,
                        backgroundImage: item.peerAvatarUrl != null &&
                                item.peerAvatarUrl!.isNotEmpty
                            ? NetworkImage(item.peerAvatarUrl!)
                            : (item.listingCoverUrl != null
                                ? NetworkImage(item.listingCoverUrl!)
                                : null),
                        child: (item.peerAvatarUrl == null ||
                                    item.peerAvatarUrl!.isEmpty) &&
                                item.listingCoverUrl == null
                            ? Text(
                                letter,
                                style: const TextStyle(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            : null,
                      ),
                  if (showPresence)
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: PresenceDot(online: online, size: 10),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontSize: 14.5,
                                  fontWeight: item.hasUnread
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                ),
                          ),
                        ),
                        Text(
                          timeLabel,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (showPresence) ...[
                          PresenceStatusText(
                            lastSeenAt: item.peerLastSeenAt,
                            fontSize: 11.5,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '·',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  fontSize: 12.5,
                                  color: AppColors.textTertiary,
                                ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            item.lastMessageText?.isNotEmpty == true
                                ? item.lastMessageText!
                                : 'Нет сообщений',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  fontSize: 12.5,
                                  color: AppColors.textSecondary,
                                ),
                          ),
                        ),
                        if (item.hasUnread) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final onDelete = onConfirmDelete;
    if (onDelete == null) return tile;

    return Dismissible(
      key: ValueKey('hide-${item.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: const Icon(Icons.delete_outline, color: AppColors.danger),
      ),
      child: tile,
    );
  }

  String _formatTime(DateTime dt) => ChatDateFormat.dialogList(dt);
}
