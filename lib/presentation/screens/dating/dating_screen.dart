import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_layout.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_mapper.dart';
import '../../../domain/models/conversation.dart';
import '../../../domain/models/dating.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../presentation/providers/chat_providers.dart';
import '../../../presentation/providers/dating_providers.dart';
import '../../../presentation/providers/repository_providers.dart';
import '../../../services/app_image_cache.dart';
import '../../../widgets/app_page_body.dart';
import '../../../widgets/city_picker.dart';
import '../../../widgets/feedback.dart';
import 'dating_match_dialog.dart';
import 'dating_moderation_sheets.dart';
import 'dating_widgets.dart';

class DatingScreen extends ConsumerStatefulWidget {
  const DatingScreen({super.key});

  @override
  ConsumerState<DatingScreen> createState() => _DatingScreenState();
}

class _DatingScreenState extends ConsumerState<DatingScreen> {
  bool _acting = false;
  bool _showingMatch = false;

  Future<void> _openChat(String conversationId) async {
    ref.read(chatFolderProvider.notifier).state = ConversationType.dating;
    ref.invalidate(conversationsByTypeProvider(ConversationType.dating));
    context.push('/main/chats/$conversationId');
  }

  Future<void> _presentActionMatch(DatingActionResult actionResult) async {
    if (!actionResult.shouldShowMatchUi || _showingMatch || !mounted) return;
    _showingMatch = true;
    try {
      final result = await showDatingMatchDialog(
        context,
        me: actionResult.me,
        other: actionResult.target,
        conversationId: actionResult.conversationId,
      );
      if (!mounted) return;
      if (result == DatingMatchDialogResult.write &&
          actionResult.conversationId != null) {
        await _openChat(actionResult.conversationId!);
      }
    } finally {
      _showingMatch = false;
    }
  }

  Future<void> _act(DatingActionType action) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      final result = await ref.read(datingFeedProvider.notifier).act(action);
      if (!mounted) return;
      if (result != null && result.shouldShowMatchUi) {
        await _presentActionMatch(result);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorMapper.map(e))),
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _pickCityFilter() async {
    final current = ref.read(datingCityFilterProvider);
    final profileCity =
        ref.read(currentProfileProvider).valueOrNull?.city.trim();
    final city = await showCityPicker(
      context,
      selected: current ?? profileCity,
      priorityCity: profileCity,
    );
    if (!mounted) return;
    if (city == null) return;
    ref.read(datingCityFilterProvider.notifier).state = city;
  }

  Future<void> _onCandidateMenu(DatingCandidate candidate) async {
    final action = await showModalBottomSheet<_DatingCardMenu>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Открыть профиль'),
              onTap: () => Navigator.pop(context, _DatingCardMenu.profile),
            ),
            ListTile(
              leading: const Icon(Icons.block, color: AppColors.danger),
              title: const Text('Заблокировать'),
              onTap: () => Navigator.pop(context, _DatingCardMenu.block),
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Пожаловаться'),
              onTap: () => Navigator.pop(context, _DatingCardMenu.report),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case _DatingCardMenu.profile:
        context.push('/main/profile/user/${candidate.id}');
      case _DatingCardMenu.block:
        final ok = await confirmBlockUser(context);
        if (!ok || !mounted) return;
        try {
          await ref.read(datingRepositoryProvider).blockUser(candidate.id);
          await ref.read(datingFeedProvider.notifier).refresh();
          ref.invalidate(datingMatchesProvider);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Пользователь заблокирован')),
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ErrorMapper.map(e))),
          );
        }
      case _DatingCardMenu.report:
        final submitted = await showReportUserSheet(
          context,
          targetUserId: candidate.id,
        );
        if (!submitted || !mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Жалоба отправлена')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(datingFeedProvider);
    final cityFilter = ref.watch(datingCityFilterProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Дейтинг'),
        actions: [
          IconButton(
            tooltip:
                cityFilter == null ? 'Фильтр: город' : 'Город: $cityFilter',
            onPressed: _pickCityFilter,
            onLongPress: cityFilter == null
                ? null
                : () =>
                    ref.read(datingCityFilterProvider.notifier).state = null,
            icon: Icon(
              cityFilter == null ? Icons.filter_list_outlined : Icons.filter_alt,
              size: 20,
              color: cityFilter == null ? null : AppColors.accent,
            ),
          ),
          TextButton(
            onPressed: () => context.push('/main/profile/dating/matches'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: const Text(
              'Совпадения',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: AppPageBody(
          child: Padding(
            padding: AppLayout.pagePadding(context, top: 8, bottom: 16),
            child: Column(
            children: [
              if (cityFilter != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: InputChip(
                    label: Text(cityFilter),
                    avatar: const Icon(Icons.location_city_outlined, size: 16),
                    onDeleted: () =>
                        ref.read(datingCityFilterProvider.notifier).state =
                            null,
                    deleteIconColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                    backgroundColor: AppColors.accentSoft,
                    labelStyle: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Expanded(
                child: feedAsync.when(
                  loading: () => const Column(
                    children: [
                      Expanded(child: DatingCardSkeleton()),
                      SizedBox(height: 16),
                      DatingActionButtons(
                        onSkip: null,
                        onLike: null,
                        enabled: false,
                      ),
                    ],
                  ),
                  error: (e, _) => Center(
                    child: AsyncErrorRetry(
                      message: ErrorMapper.map(e),
                      onRetry: () =>
                          ref.read(datingFeedProvider.notifier).refresh(),
                    ),
                  ),
                  data: (list) {
                    if (list.isEmpty) {
                      return const _DatingEmptyState();
                    }

                    final candidate = list.first;
                    // Warm current + next candidates while user swipes.
                    AppImageCache.prefetch([
                      for (final c in list.take(3)) ...c.photoUrls,
                    ], limit: 12);

                    return Column(
                      children: [
                        Expanded(
                          child: Stack(
                            children: [
                              KeyedSubtree(
                                key: ValueKey(candidate.id),
                                child: DatingProfileCard(
                                  candidate: candidate,
                                  onOpenProfile: () => context.push(
                                    '/main/profile/user/${candidate.id}',
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Material(
                                  color: AppColors.scrim,
                                  shape: const CircleBorder(),
                                  child: IconButton(
                                    tooltip: 'Ещё',
                                    icon: const Icon(
                                      Icons.more_vert,
                                      color: AppColors.textPrimary,
                                      size: 20,
                                    ),
                                    onPressed: () =>
                                        _onCandidateMenu(candidate),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        DatingActionButtons(
                          busy: _acting,
                          enabled: !_acting,
                          onSkip: () => _act(DatingActionType.skip),
                          onLike: () => _act(DatingActionType.like),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _DatingCardMenu { profile, block, report }

class _DatingEmptyState extends StatelessWidget {
  const _DatingEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(AppRadii.badge),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.groups_outlined,
                color: AppColors.accent,
                size: 28,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Пока никого нет',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Попробуйте другой город или зайдите позже',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
