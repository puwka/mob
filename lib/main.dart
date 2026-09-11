import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/supabase_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'presentation/providers/presence_providers.dart';
import 'services/mapkit_bootstrap.dart';
import 'services/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.surface,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  await dotenv.load(fileName: '.env');
  await initializeDateFormatting('ru');

  await initMapkitIfNeeded(
    dotenv.env['YANDEX_MAPKIT_API_KEY']?.trim() ?? '',
  );

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  await PushNotificationService.instance.init();

  runApp(const ProviderScope(child: TacticalApp()));
}

class TacticalApp extends ConsumerStatefulWidget {
  const TacticalApp({super.key});

  @override
  ConsumerState<TacticalApp> createState() => _TacticalAppState();
}

class _TacticalAppState extends ConsumerState<TacticalApp> {
  @override
  void initState() {
    super.initState();
    PushNotificationService.instance.onOpenLocation = (location) {
      ref.read(goRouterProvider).go(location);
    };
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
      title: 'Мой Страйкбол',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
      builder: (context, child) {
        final content = PresenceLifecycle(
          child: child ?? const SizedBox.shrink(),
        );
        return MediaQuery.withClampedTextScaling(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.25,
          child: content,
        );
      },
    );
  }
}
