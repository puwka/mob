import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../core/utils/presence.dart';
import '../../../domain/models/conversation.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../presentation/providers/chat_providers.dart';
import '../../../presentation/providers/presence_providers.dart';
import '../../../widgets/feedback.dart';
import '../../../widgets/presence_status.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  var _stickToBottom = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final atBottom = _scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 48;
    _stickToBottom = atBottom;

    if (_scroll.position.pixels <= 48) {
      ref.read(chatMessagesProvider(widget.conversationId).notifier).loadMore();
    }
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (animated) {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text;
    final ok = await ref
        .read(chatMessagesProvider(widget.conversationId).notifier)
        .send(text);
    if (ok) {
      _input.clear();
      _stickToBottom = true;
      _scrollToBottom();
    } else if (mounted) {
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
      if (_stickToBottom &&
          (prev?.messages.length ?? 0) < next.messages.length) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
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
                    d.type == ConversationType.market);

            return Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.surfaceElevated,
                      backgroundImage: d.peerAvatarUrl != null
                          ? NetworkImage(d.peerAvatarUrl!)
                          : null,
                      child: d.peerAvatarUrl == null
                          ? Text(
                              d.displayTitle.isNotEmpty
                                  ? d.displayTitle[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(fontSize: 12),
                            )
                          : null,
                    ),
                    if (showPresence)
                      Positioned(
                        right: -1,
                        bottom: -1,
                        child: PresenceDot(
                          online: Presence.isOnline(lastSeen),
                          size: 9,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15),
                      ),
                      if (showPresence)
                        PresenceStatusText(lastSeenAt: lastSeen)
                      else
                        Text(
                          d.type.folderLabel,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
          orElse: () => const Text('Диалог'),
        ),
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
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            itemCount: messagesState.messages.length +
                                (messagesState.loadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (messagesState.loadingMore && index == 0) {
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
                              final msgIndex = messagesState.loadingMore
                                  ? index - 1
                                  : index;
                              final msg = messagesState.messages[msgIndex];
                              final mine = msg.senderId == myId;
                              return _Bubble(message: msg, mine: mine);
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
              child: Row(
                children: [
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
                      onTap: messagesState.sending ? null : _send,
                      borderRadius: BorderRadius.circular(AppRadii.button),
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
                              : const Icon(
                                  Icons.send,
                                  size: 18,
                                  color: Color(0xFF121408),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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
  const _Bubble({required this.message, required this.mine});

  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm').format(message.createdAt.toLocal());
    final bg = mine ? AppColors.accentSoft : AppColors.surfaceElevated;
    final border = mine ? AppColors.accentDim : AppColors.border;
    final align = mine ? Alignment.centerRight : Alignment.centerLeft;

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
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
              Text(
                message.isDeleted ? 'Сообщение удалено' : message.text,
                style: TextStyle(
                  fontSize: 14.5,
                  color: message.isDeleted
                      ? AppColors.textTertiary
                      : AppColors.textPrimary,
                  fontStyle:
                      message.isDeleted ? FontStyle.italic : FontStyle.normal,
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
      ),
    );
  }
}
