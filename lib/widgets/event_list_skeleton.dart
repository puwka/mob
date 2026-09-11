import 'package:flutter/material.dart';

import '../core/layout/app_layout.dart';
import '../core/theme/app_colors.dart';

class EventListSkeleton extends StatelessWidget {
  const EventListSkeleton({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: AppLayout.pagePadding(context),
      itemCount: count,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) => const _SkeletonRow(),
    );
  }
}

class _SkeletonRow extends StatefulWidget {
  const _SkeletonRow();

  @override
  State<_SkeletonRow> createState() => _SkeletonRowState();
}

class _SkeletonRowState extends State<_SkeletonRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = AppLayout.eventListThumb(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.35 + _controller.value * 0.35,
          child: child,
        );
      },
      child: Container(
        height: h,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: h,
              color: AppColors.surfaceElevated,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 13,
                      width: 150,
                      color: AppColors.surfaceElevated,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 10,
                      width: 110,
                      color: AppColors.surfaceElevated,
                    ),
                    const Spacer(),
                    Container(
                      height: 10,
                      width: 70,
                      color: AppColors.surfaceElevated,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
