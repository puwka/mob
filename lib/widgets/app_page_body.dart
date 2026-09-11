import 'package:flutter/material.dart';

import '../core/layout/app_layout.dart';

/// Centers content and caps width for large phones / tablets.
class AppPageBody extends StatelessWidget {
  const AppPageBody({
    super.key,
    required this.child,
    this.maxWidth = AppLayout.contentMaxWidth,
    this.safeArea = false,
  });

  final Widget child;
  final double maxWidth;
  final bool safeArea;

  @override
  Widget build(BuildContext context) {
    Widget body = AppLayout.constrain(
      context: context,
      maxWidth: maxWidth,
      child: child,
    );
    if (safeArea) {
      body = SafeArea(child: body);
    }
    return body;
  }
}
