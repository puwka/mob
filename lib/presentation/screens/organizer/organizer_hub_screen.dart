import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../presentation/providers/organizer_wallet_providers.dart';
import '../../../widgets/app_card.dart';

class OrganizerHubScreen extends ConsumerWidget {
  const OrganizerHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOrganizer =
        ref.watch(currentProfileProvider).valueOrNull?.isOrganizer ?? false;

    if (!isOrganizer) {
      return Scaffold(
        appBar: AppBar(title: const Text('Организатор')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Доступ только для организаторов',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }

    final stats = ref.watch(organizerDashboardProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Организатор')),
      body: RefreshIndicator(
        color: AppColors.accent,
        onRefresh: () =>
            ref.read(organizerDashboardProvider.notifier).refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const SectionTitle(title: 'Сводка'),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    value: '${stats?.eventsCount ?? 0}',
                    label: 'Мероприятия',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCard(
                    value: '${stats?.participantsCount ?? 0}',
                    label: 'Участники',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    value: '${stats?.confirmedToday ?? 0}',
                    label: 'Сегодня',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCard(
                    value: stats?.balanceLabel ?? '0 CR',
                    label: 'Заработано',
                    accent: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const SectionTitle(title: 'Быстрые действия'),
            _OrgTile(
              icon: Icons.map_outlined,
              title: 'Мои полигоны',
              subtitle: 'Площадки и адреса на карте',
              onTap: () => context.push('/main/profile/organizer/polygons'),
            ),
            const SizedBox(height: 8),
            _OrgTile(
              icon: Icons.add_circle_outline,
              title: 'Создать мероприятие',
              subtitle: 'Новый ивент',
              onTap: () =>
                  context.push('/main/profile/organizer/events/create'),
            ),
            const SizedBox(height: 8),
            _OrgTile(
              icon: Icons.qr_code_scanner,
              title: 'Сканировать QR',
              subtitle: 'Подтверждение присутствия',
              onTap: () => context.push('/main/profile/organizer/scanner'),
            ),
            const SizedBox(height: 8),
            _OrgTile(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Баланс',
              subtitle: stats?.balanceLabel ?? 'История начислений',
              onTap: () => context.push('/main/profile/organizer/balance'),
            ),
            const SizedBox(height: 8),
            _OrgTile(
              icon: Icons.event_note_outlined,
              title: 'Мои мероприятия',
              subtitle: 'Список созданных ивентов',
              onTap: () => context.push('/main/profile/organizer/events'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    this.accent = false,
  });

  final String value;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      accentBorder: accent,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: accent ? AppColors.accent : AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrgTile extends StatelessWidget {
  const _OrgTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.accentDim),
            ),
            child: Icon(icon, size: 20, color: AppColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            size: 18,
            color: AppColors.textTertiary,
          ),
        ],
      ),
    );
  }
}
