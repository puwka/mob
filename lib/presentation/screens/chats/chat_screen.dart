import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/layout/app_layout.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../core/utils/presence.dart';
import '../../../domain/models/conversation.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../presentation/providers/chat_providers.dart';
import '../../../presentation/providers/clan_providers.dart';
import '../../../presentation/providers/dating_providers.dart';
import '../../../presentation/providers/notification_providers.dart';
import '../../../presentation/providers/presence_providers.dart';
import '../../../presentation/providers/repository_providers.dart';
import '../../../services/chat_voice_recorder.dart';
import '../../../widgets/app_network_image.dart';
import '../../../widgets/feedback.dart';
import '../../../widgets/photo_lightbox.dart';
import '../../../widgets/presence_status.dart';
import '../dating/dating_moderation_sheets.dart';

enum _ChatPeerAction {
  block,
  report,
  delete,
  muteNotifications,
  unmuteNotifications,
  participants,
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _voiceRecorder = ChatVoiceRecorder();
  var _stickToBottom = true;
  var _recording = false;
  var _hasText = false;
  Timer? _recordTicker;
  ChatMessage? _replyTo;

  Future<void> _onPeerAction(
    _ChatPeerAction action, {
    String? peerId,
    ConversationType? type,
  }) async {
    switch (action) {
      case _ChatPeerAction.block:
        if (peerId == null) return;
        final ok = await confirmBlockUser(context);
        if (!ok || !mounted) return;
        try {
          await ref.read(datingRepositoryProvider).blockUser(peerId);
          ref.invalidate(datingFeedProvider);
          ref.invalidate(datingMatchesProvider);
          ref.invalidate(conversationsByTypeProvider(ConversationType.dating));
          ref.invalidate(conversationsByTypeProvider(ConversationType.user));
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Пользователь заблокирован')),
          );
          context.go('/main/chats');
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ErrorMapper.map(e))),
          );
        }
      case _ChatPeerAction.report:
        if (peerId == null) return;
        final submitted =
            await showReportUserSheet(context, targetUserId: peerId);
        if (!submitted || !mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Жалоба отправлена')),
        );
      case _ChatPeerAction.delete:
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
        if (confirmed != true || !mounted) return;
        try {
          await ref
              .read(chatRepositoryProvider)
              .hideConversation(widget.conversationId);
          if (type != null) {
            ref.invalidate(conversationsByTypeProvider(type));
          }
          ref.invalidate(folderUnreadProvider);
          if (!mounted) return;
          context.go('/main/chats');
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ErrorMapper.map(e))),
          );
        }
      case _ChatPeerAction.muteNotifications:
      case _ChatPeerAction.unmuteNotifications:
        final muted = action == _ChatPeerAction.muteNotifications;
        try {
          await ref.read(notificationRepositoryProvider).setConversationMuted(
                conversationId: widget.conversationId,
                muted: muted,
              );
          ref.invalidate(
            conversationNotificationsMutedProvider(widget.conversationId),
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                muted
                    ? 'Уведомления от этого диалога выключены'
                    : 'Уведомления включены',
              ),
            ),
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ErrorMapper.map(e))),
          );
        }
      case _ChatPeerAction.participants:
        if (!mounted) return;
        context.push('/main/chats/${widget.conversationId}/participants');
    }
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _input.addListener(() {
      final next = _input.text.trim().isNotEmpty;
      if (next != _hasText) setState(() => _hasText = next);
    });
  }

  @override
  void dispose() {
    _recordTicker?.cancel();
    unawaited(_voiceRecorder.dispose());
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    // reverse: true → 0 = newest (bottom), maxScrollExtent = oldest (top)
    final atBottom = _scroll.position.pixels <= 48;
    _stickToBottom = atBottom;

    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 48) {
      ref.read(chatMessagesProvider(widget.conversationId).notifier).loadMore();
    }
  }

  void _scrollToBottom({bool animated = true}) {
    void jump() {
      if (!_scroll.hasClients) return;
      const target = 0.0;
      if (animated) {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(target);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      jump();
      // Second frame: list extent can grow after first layout (images, etc.).
      WidgetsBinding.instance.addPostFrameCallback((_) => jump());
    });
  }

  String get _recordElapsedLabel {
    final sec = (_voiceRecorder.elapsedMs / 1000).floor().clamp(0, 999);
    final m = sec ~/ 60;
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _send() async {
    final text = _input.text;
    final reply = _replyTo;
    final ok = await ref
        .read(chatMessagesProvider(widget.conversationId).notifier)
        .send(
          text,
          replyToMessageId: reply?.id,
          replyTo: reply == null ? null : ChatReplyPreview.fromMessage(reply),
        );
    if (!mounted) return;
    if (ok) {
      _input.clear();
      setState(() => _replyTo = null);
      _stickToBottom = true;
      _scrollToBottom();
    } else {
      final err = ref.read(chatMessagesProvider(widget.conversationId)).error;
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _startReply(ChatMessage message) {
    if (message.isDeleted || message.pending) return;
    setState(() => _replyTo = message);
  }

  Future<void> _startRecording() async {
    try {
      final allowed = await _voiceRecorder.hasPermission();
      if (!allowed) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Нужен доступ к микрофону'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      await _voiceRecorder.start();
      _recordTicker?.cancel();
      _recordTicker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        if (_voiceRecorder.elapsedMs >= 60000) {
          unawaited(_stopAndSendVoice());
          return;
        }
        setState(() {});
      });
      if (mounted) setState(() => _recording = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().contains('NotAllowedError') ||
                    e.toString().toLowerCase().contains('permission')
                ? 'Нужен доступ к микрофону'
                : 'Не удалось начать запись: ${ErrorMapper.map(e)}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _cancelRecording() async {
    _recordTicker?.cancel();
    await _voiceRecorder.cancel();
    if (mounted) setState(() => _recording = false);
  }

  Future<void> _stopAndSendVoice() async {
    if (!_recording) return;
    _recordTicker?.cancel();
    if (mounted) setState(() => _recording = false);

    VoiceCapture? capture;
    try {
      capture = await _voiceRecorder.stop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorMapper.map(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (capture == null ||
        capture.bytes.isEmpty ||
        capture.durationMs < 500) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Запись слишком короткая'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final reply = _replyTo;
    final ok = await ref
        .read(chatMessagesProvider(widget.conversationId).notifier)
        .sendVoice(
          bytes: capture.bytes,
          durationMs: capture.durationMs.clamp(500, 120000),
          contentType: capture.contentType,
          extension: capture.extension,
          replyToMessageId: reply?.id,
          replyTo: reply == null ? null : ChatReplyPreview.fromMessage(reply),
        );
    if (!mounted) return;
    if (ok) {
      setState(() => _replyTo = null);
      _stickToBottom = true;
      _scrollToBottom();
    } else {
      final err = ref.read(chatMessagesProvider(widget.conversationId)).error;
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    const maxImages = 10;
    final files = await ImagePicker().pickMultiImage(
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 88,
      limit: maxImages,
    );
    if (files.isEmpty) return;

    if (files.length > maxImages) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Максимум $maxImages фото за сообщение'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    final images = <Uint8List>[];
    for (final file in files.take(maxImages)) {
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty) images.add(Uint8List.fromList(bytes));
    }
    if (images.isEmpty) return;

    final reply = _replyTo;
    final ok = await ref
        .read(chatMessagesProvider(widget.conversationId).notifier)
        .sendImages(
          images: images,
          replyToMessageId: reply?.id,
          replyTo: reply == null ? null : ChatReplyPreview.fromMessage(reply),
        );
    if (!mounted) return;
    if (ok) {
      setState(() => _replyTo = null);
      _stickToBottom = true;
      _scrollToBottom();
    } else {
      final err = ref.read(chatMessagesProvider(widget.conversationId)).error;
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync =
        ref.watch(conversationDetailProvider(widget.conversationId));
    final messagesState =
        ref.watch(chatMessagesProvider(widget.conversationId));
    final myId = ref.watch(authRepositoryProvider).currentUser?.id;

    ref.listen(chatMessagesProvider(widget.conversationId), (prev, next) {
      final wasEmpty = (prev?.messages.isEmpty ?? true);
      final grew = (prev?.messages.length ?? 0) < next.messages.length;
      if (wasEmpty && next.messages.isNotEmpty) {
        _stickToBottom = true;
        _scrollToBottom(animated: false);
        return;
      }
      if (_stickToBottom && grew) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 0,
        title: detailAsync.maybeWhen(
          data: (d) {
            final peerId = d.peerUserId;
            final liveSeen = peerId != null
                ? ref.watch(userLastSeenProvider(peerId)).valueOrNull
                : null;
            final lastSeen = liveSeen ?? d.peerLastSeenAt;
            final showPresence = peerId != null &&
                (d.type == ConversationType.user ||
                    d.type == ConversationType.dating ||
                    d.type == ConversationType.market);

            return InkWell(
              onTap: peerId != null && peerId != myId
                  ? () => context.push('/main/profile/user/$peerId')
                  : null,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.surfaceElevated,
                          backgroundImage: d.peerAvatarUrl != null
                              ? NetworkImage(d.peerAvatarUrl!)
                              : null,
                          child: d.peerAvatarUrl == null
                              ? Text(
                                  d.displayTitle.isNotEmpty
                                      ? d.displayTitle[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              : null,
                        ),
                        if (showPresence)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: PresenceDot(
                              online: Presence.isOnline(lastSeen),
                              size: 11,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                        Text(
                          d.type == ConversationType.market &&
                                  (d.peerNickname?.trim().isNotEmpty ?? false)
                              ? d.peerNickname!.trim()
                              : d.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                          if (showPresence)
                            PresenceStatusText(
                              lastSeenAt: lastSeen,
                              fontSize: 13,
                            )
                        else if (d.type == ConversationType.dating)
                          const Text(
                            'Дейтинг',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textTertiary,
                              fontWeight: FontWeight.w400,
                            ),
                          )
                        else if (d.type == ConversationType.city)
                          const Text(
                            'Чат города',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textTertiary,
                              fontWeight: FontWeight.w400,
                            ),
                          )
                        else if (d.type == ConversationType.market &&
                            (d.listingTitle?.trim().isNotEmpty ?? false))
                          Text(
                            d.listingTitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textTertiary,
                              fontWeight: FontWeight.w400,
                            ),
                          )
                        else
                          Text(
                            d.type.folderLabel,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textTertiary,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          orElse: () => const Text('Диалог'),
        ),
        actions: [
          detailAsync.maybeWhen(
            data: (d) {
              final peerId = d.peerUserId;
              final canModeratePeer = peerId != null &&
                  peerId != myId &&
                  (d.type == ConversationType.dating ||
                      d.type == ConversationType.user);
              final canDelete = d.type == ConversationType.user ||
                  d.type == ConversationType.market ||
                  d.type == ConversationType.dating;
              final notificationsMuted = ref
                      .watch(
                        conversationNotificationsMutedProvider(
                          widget.conversationId,
                        ),
                      )
                      .valueOrNull ??
                  false;
              return PopupMenuButton<_ChatPeerAction>(
                tooltip: 'Ещё',
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (action) => _onPeerAction(
                  action,
                  peerId: peerId,
                  type: d.type,
                ),
                itemBuilder: (context) => [
                  if (canModeratePeer) ...const [
                    PopupMenuItem(
                      value: _ChatPeerAction.block,
                      child: Text('Заблокировать'),
                    ),
                    PopupMenuItem(
                      value: _ChatPeerAction.report,
                      child: Text('Пожаловаться'),
                    ),
                  ],
                  if (d.type == ConversationType.clan ||
                      d.type == ConversationType.city ||
                      d.type == ConversationType.event)
                    const PopupMenuItem(
                      value: _ChatPeerAction.participants,
                      child: Text('Участники'),
                    ),
                  PopupMenuItem(
                    value: notificationsMuted
                        ? _ChatPeerAction.unmuteNotifications
                        : _ChatPeerAction.muteNotifications,
                    child: Text(
                      notificationsMuted
                          ? 'Включить уведомления'
                          : 'Не уведомлять',
                    ),
                  ),
                  if (canDelete)
                    const PopupMenuItem(
                      value: _ChatPeerAction.delete,
                      child: Text('Удалить диалог'),
                    ),
                ],
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: Column(
        children: [
          detailAsync.maybeWhen(
            data: (d) {
              if (d.type != ConversationType.market || d.listingId == null) {
                return const SizedBox.shrink();
              }
              return _ListingBanner(
                title: d.listingTitle ?? 'Объявление',
                price: d.listingPrice,
                coverUrl: d.listingCoverUrl,
                onTap: () => context.push('/main/market/${d.listingId}'),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
          Expanded(
            child: messagesState.loading && messagesState.messages.isEmpty
                ? const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : messagesState.error != null &&
                        messagesState.messages.isEmpty
                    ? Center(
                        child: AsyncErrorRetry(
                          message: ErrorMapper.map(messagesState.error!),
                          onRetry: () => ref
                              .read(
                                chatMessagesProvider(widget.conversationId)
                                    .notifier,
                              )
                              .loadInitial(),
                        ),
                      )
                    : messagesState.messages.isEmpty
                        ? const Center(
                            child: Text(
                              'Начните переписку',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          )
                        : ListView.builder(
                            controller: _scroll,
                            reverse: true,
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            itemCount: messagesState.messages.length +
                                (messagesState.loadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              final messages = messagesState.messages;
                              // reverse: index 0 at bottom = newest message
                              if (messagesState.loadingMore &&
                                  index == messages.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Center(
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                );
                              }
                              final msgIndex = messages.length - 1 - index;
                              final msg = messages[msgIndex];
                              final mine = msg.senderId == myId;
                              final prev = msgIndex > 0
                                  ? messages[msgIndex - 1]
                                  : null;
                              final type = detailAsync.valueOrNull?.type;
                              final isGroupChat = type == ConversationType.clan ||
                                  type == ConversationType.city ||
                                  type == ConversationType.event;
                              final isNewSender =
                                  prev == null || prev.senderId != msg.senderId;
                              // Groups: nick + avatar on sender change.
                              // 1-on-1: avatar only (no nick in bubble).
                              final showSenderName = isGroupChat && isNewSender;
                              final showAvatar = isNewSender;
                              return _SwipeToReply(
                                enabled: !msg.isDeleted && !msg.pending,
                                onReply: () => _startReply(msg),
                                child: _Bubble(
                                  message: msg,
                                  mine: mine,
                                  showSenderName: showSenderName,
                                  showAvatar: showAvatar,
                                  onOpenProfile: msg.senderId == myId
                                      ? null
                                      : () => context.push(
                                            '/main/profile/user/${msg.senderId}',
                                          ),
                                ),
                              );
                            },
                          ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  top: BorderSide(color: AppColors.borderSubtle),
                ),
              ),
              child: () {
                final mute = ref.watch(chatMuteProvider(widget.conversationId))
                    .valueOrNull;
                if (mute != null && mute.isActive) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      mute.reason?.trim().isNotEmpty == true
                          ? 'Мут: ${mute.reason}'
                          : 'Вам запрещено писать в этот чат',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  );
                }

                final detail = detailAsync.valueOrNull;
                if (detail?.type == ConversationType.clan) {
                  final clanId = detail!.clanId;
                  final role = clanId == null
                      ? null
                      : ref.watch(myClanRoleProvider(clanId)).valueOrNull;
                  final officersBlocked = detail.clanChannel ==
                          ClanChatChannel.officers &&
                      (role == null || !role.isLeadership);
                  if (role == null || officersBlocked) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'Писать в чат клана можно только после вступления',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    );
                  }
                }

                final composer = _recording
                  ? Row(
                      children: [
                        IconButton(
                          tooltip: 'Отмена',
                          onPressed: messagesState.sending
                              ? null
                              : _cancelRecording,
                          icon: const Icon(
                            Icons.close,
                            color: AppColors.danger,
                          ),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              const _RecordingPulseDot(),
                              const SizedBox(width: 10),
                              Text(
                                'Запись $_recordElapsedLabel',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Material(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(AppRadii.button),
                          child: InkWell(
                            onTap: messagesState.sending
                                ? null
                                : _stopAndSendVoice,
                            borderRadius:
                                BorderRadius.circular(AppRadii.button),
                            child: const SizedBox(
                              width: 42,
                              height: 42,
                              child: Icon(
                                Icons.send,
                                size: 18,
                                color: Color(0xFF121408),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Material(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(AppRadii.button),
                          child: InkWell(
                            onTap: messagesState.sending
                                ? null
                                : _pickAndSendImage,
                            borderRadius:
                                BorderRadius.circular(AppRadii.button),
                            child: const SizedBox(
                              width: 42,
                              height: 42,
                              child: Icon(
                                Icons.image_outlined,
                                size: 20,
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: TextField(
                              controller: _input,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(),
                              style: const TextStyle(fontSize: 14.5),
                              decoration: const InputDecoration(
                                hintText: 'Текст сообщения...',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(AppRadii.button),
                          child: InkWell(
                            onTap: messagesState.sending
                                ? null
                                : (_hasText ? _send : _startRecording),
                            borderRadius:
                                BorderRadius.circular(AppRadii.button),
                            child: SizedBox(
                              width: 42,
                              height: 42,
                              child: Center(
                                child: messagesState.sending
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFF121408),
                                        ),
                                      )
                                    : Icon(
                                        _hasText ? Icons.send : Icons.mic,
                                        size: 18,
                                        color: const Color(0xFF121408),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_replyTo != null) ...[
                      _ReplyComposerBar(
                        message: _replyTo!,
                        onClose: () => setState(() => _replyTo = null),
                      ),
                      const SizedBox(height: 8),
                    ],
                    composer,
                  ],
                );
              }(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({
    required this.enabled,
    required this.onReply,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onReply;
  final Widget child;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  static const _maxDrag = 72.0;
  static const _trigger = 48.0;

  double _dx = 0;

  void _reset() {
    setState(() => _dx = 0);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final progress = (-_dx / _trigger).clamp(0.0, 1.0);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (details) {
        final next = (_dx + details.delta.dx).clamp(-_maxDrag, 0.0);
        setState(() => _dx = next);
      },
      onHorizontalDragEnd: (_) {
        final shouldReply = -_dx >= _trigger;
        _reset();
        if (shouldReply) widget.onReply();
      },
      onHorizontalDragCancel: _reset,
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          Opacity(
            opacity: progress,
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                Icons.reply_rounded,
                size: 22,
                color: AppColors.accent.withValues(alpha: 0.9),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(_dx, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

class _ReplyComposerBar extends StatelessWidget {
  const _ReplyComposerBar({
    required this.message,
    required this.onClose,
  });

  final ChatMessage message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final preview = ChatReplyPreview.fromMessage(message);
    return Row(
      children: [
        Container(
          width: 3,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                preview.displaySenderName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
              Text(
                preview.previewText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Отменить ответ',
          onPressed: onClose,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close, size: 18),
        ),
      ],
    );
  }
}

class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({
    required this.preview,
    required this.mine,
  });

  final ChatReplyPreview preview;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      decoration: BoxDecoration(
        color: mine
            ? const Color(0x22000000)
            : AppColors.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: AppColors.accent, width: 2.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            preview.displaySenderName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
          Text(
            preview.previewText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ListingBanner extends StatelessWidget {
  const _ListingBanner({
    required this.title,
    required this.onTap,
    this.price,
    this.coverUrl,
  });

  final String title;
  final double? price;
  final String? coverUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final priceLabel = price == null
        ? null
        : '${price!.toStringAsFixed(0)} ₽';

    return Material(
      color: AppColors.card,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.borderSubtle),
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: coverUrl == null
                      ? Container(
                          color: AppColors.surfaceElevated,
                          child: const Icon(
                            Icons.image_outlined,
                            size: 18,
                            color: AppColors.textTertiary,
                          ),
                        )
                      : Image.network(coverUrl!, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (priceLabel != null)
                      Text(
                        priceLabel,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textTertiary,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.showSenderName,
    required this.showAvatar,
    this.onOpenProfile,
  });

  final ChatMessage message;
  final bool mine;
  final bool showSenderName;
  final bool showAvatar;
  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm').format(message.createdAt.toLocal());
    final bg = mine ? AppColors.accentSoft : AppColors.surfaceElevated;
    final border = mine ? AppColors.accentDim : AppColors.border;
    final letter = message.displaySenderName.isNotEmpty
        ? message.displaySenderName[0].toUpperCase()
        : '?';
    final avatar = message.senderAvatarUrl;

    final bubble = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.72,
      ),
      child: Container(
        margin: EdgeInsets.only(
          top: showAvatar ? 6 : 2,
          bottom: 2,
        ),
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (showSenderName) ...[
              GestureDetector(
                onTap: onOpenProfile,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: message.displaySenderName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: mine ? AppColors.accent : AppColors.accent,
                        ),
                      ),
                      if (message.senderClanRole != null)
                        TextSpan(
                          text: ' · ${message.senderClanRole!.labelRu}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 3),
            ],
            if (message.replyTo != null && !message.isDeleted) ...[
              _ReplyQuote(
                preview: message.replyTo!,
                mine: mine,
              ),
              const SizedBox(height: 5),
            ],
            if (message.isDeleted)
              const Text(
                'Сообщение удалено',
                style: TextStyle(
                  fontSize: 14.5,
                  color: AppColors.textTertiary,
                  fontStyle: FontStyle.italic,
                ),
              )
            else if (message.isVoice)
              _VoicePlayer(
                url: message.audioUrl,
                durationMs: message.audioDurationMs,
                pending: message.pending,
              )
            else if (message.isImage)
              _ChatImageBubble(
                urls: message.resolvedImageUrls,
                pending: message.pending,
              )
            else
              Text(
                message.text,
                style: const TextStyle(
                  fontSize: 14.5,
                  color: AppColors.textPrimary,
                ),
              ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.pending)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  ),
                if (message.failed)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.error_outline,
                      size: 12,
                      color: AppColors.danger,
                    ),
                  ),
                Text(
                  time,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final avatarWidget = GestureDetector(
      onTap: onOpenProfile,
      child: CircleAvatar(
        radius: 16,
        backgroundColor: AppColors.surfaceElevated,
        backgroundImage:
            avatar != null && avatar.isNotEmpty ? NetworkImage(avatar) : null,
        child: avatar == null || avatar.isEmpty
            ? Text(
                letter,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              )
            : null,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!mine) ...[
            if (showAvatar) avatarWidget else const SizedBox(width: 32),
            const SizedBox(width: 8),
          ],
          bubble,
          if (mine) ...[
            const SizedBox(width: 8),
            if (showAvatar) avatarWidget else const SizedBox(width: 32),
          ],
        ],
      ),
    );
  }
}

class _RecordingPulseDot extends StatefulWidget {
  const _RecordingPulseDot();

  @override
  State<_RecordingPulseDot> createState() => _RecordingPulseDotState();
}

class _RecordingPulseDotState extends State<_RecordingPulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = Curves.easeOut.transform(_controller.value);
          final ringScale = 0.55 + t * 0.9;
          final ringOpacity = (1.0 - t).clamp(0.0, 1.0);

          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: ringScale,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.danger.withValues(alpha: 0.28 * ringOpacity),
                    border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.55 * ringOpacity),
                      width: 1.2,
                    ),
                  ),
                ),
              ),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(
                    alpha: 0.75 + 0.25 * (1 - t),
                  ),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ChatImageBubble extends StatelessWidget {
  const _ChatImageBubble({
    required this.urls,
    required this.pending,
  });

  final List<String> urls;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final cleaned = [
      for (final u in urls)
        if (u.trim().isNotEmpty) u.trim(),
    ];
    if (cleaned.isEmpty) {
      return SizedBox(
        width: 160,
        height: 120,
        child: Center(
          child: pending
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.broken_image_outlined,
                  color: AppColors.textTertiary),
        ),
      );
    }

    if (cleaned.length == 1) {
      return _ChatImageThumb(
        url: cleaned.first,
        pending: pending,
        onTap: () => showPhotoLightbox(
          context,
          urls: cleaned,
          initialIndex: 0,
        ),
      );
    }

    final max = AppLayout.chatImageMax(context);
    final gap = 3.0;
    final cell = (max - gap) / 2;

    Widget tile(int index) {
      return _ChatImageThumb(
        url: cleaned[index],
        pending: pending,
        width: cell,
        height: cell,
        onTap: () => showPhotoLightbox(
          context,
          urls: cleaned,
          initialIndex: index,
        ),
      );
    }

    // 2–4: 2x2-ish; 5+: wrap rows of 2
    final rows = <Widget>[];
    for (var i = 0; i < cleaned.length; i += 2) {
      final hasSecond = i + 1 < cleaned.length;
      rows.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            tile(i),
            if (hasSecond) ...[
              SizedBox(width: gap),
              tile(i + 1),
            ],
          ],
        ),
      );
      if (i + 2 < cleaned.length) {
        rows.add(SizedBox(height: gap));
      }
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: max),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }
}

class _ChatImageThumb extends StatelessWidget {
  const _ChatImageThumb({
    required this.url,
    required this.pending,
    required this.onTap,
    this.width,
    this.height,
  });

  final String url;
  final bool pending;
  final VoidCallback onTap;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final max = AppLayout.chatImageMax(context);
    final w = width ?? max;
    final h = height ?? max;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AppNetworkImage(
                url: url,
                fit: BoxFit.cover,
                width: w,
                height: h,
                showSpinner: true,
                filterQuality: FilterQuality.medium,
                debugLabel: 'chat-image',
              ),
              if (pending)
                const ColoredBox(
                  color: Color(0x66000000),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoicePlayer extends StatefulWidget {
  const _VoicePlayer({
    required this.url,
    required this.durationMs,
    required this.pending,
  });

  final String? url;
  final int? durationMs;
  final bool pending;

  @override
  State<_VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<_VoicePlayer> {
  final _player = AudioPlayer();
  var _playing = false;
  var _loading = false;
  Duration _position = Duration.zero;
  Duration? _duration;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerState>? _stateSub;

  @override
  void initState() {
    super.initState();
    _posSub = _player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _stateSub = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _playing = state.playing;
        if (state.processingState == ProcessingState.completed) {
          _playing = false;
          _position = Duration.zero;
          unawaited(_player.seek(Duration.zero));
          unawaited(_player.pause());
        }
      });
    });
    if (widget.durationMs != null) {
      _duration = Duration(milliseconds: widget.durationMs!);
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _stateSub?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  String _fmt(Duration d) {
    final total = d.inSeconds.clamp(0, 9999);
    final m = total ~/ 60;
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _toggle() async {
    final url = widget.url;
    if (url == null || url.isEmpty || widget.pending) return;
    try {
      if (_playing) {
        await _player.pause();
        return;
      }
      if (_player.audioSource == null) {
        setState(() => _loading = true);
        await _player.setUrl(url);
        _duration = _player.duration ?? _duration;
        setState(() => _loading = false);
      }
      await _player.play();
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось воспроизвести'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _duration ??
        (widget.durationMs != null
            ? Duration(milliseconds: widget.durationMs!)
            : Duration.zero);
    final progress = total.inMilliseconds <= 0
        ? 0.0
        : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

    return SizedBox(
      width: AppLayout.chatVoiceWidth(context),
      child: Row(
        children: [
          InkWell(
            onTap: widget.pending || _loading ? null : _toggle,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
              child: _loading || widget.pending
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF121408),
                      ),
                    )
                  : Icon(
                      _playing ? Icons.pause : Icons.play_arrow,
                      size: 20,
                      color: const Color(0xFF121408),
                    ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    backgroundColor: AppColors.border,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_fmt(_position)} / ${_fmt(total)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
