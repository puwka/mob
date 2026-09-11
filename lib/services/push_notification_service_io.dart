import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../firebase_options.dart';

/// Background isolate handler — must be top-level.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

/// Registers FCM tokens and opens deep links from system notifications.
class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  static const _androidChannel = AndroidNotificationChannel(
    'moystrikbol_default',
    'Уведомления',
    description: 'Сообщения, игры и дейтинг',
    importance: Importance.high,
  );

  final _local = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  String? _token;
  void Function(String location)? onOpenLocation;

  bool get isReady => _ready;

  Future<void> init() async {
    if (_ready) return;
    if (!DefaultFirebaseOptions.isConfigured) {
      debugPrint('[PUSH] Firebase не настроен — системные уведомления отключены');
      return;
    }

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      debugPrint('[PUSH] Firebase.initializeApp failed: $e');
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        final loc = _locationFromPayload(response.payload);
        if (loc != null) onOpenLocation?.call(loc);
      },
    );

    if (Platform.isAndroid) {
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_androidChannel);
    }

    final messaging = FirebaseMessaging.instance;
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('[PUSH] Permission denied');
      return;
    }

    if (Platform.isIOS) {
      await messaging.getAPNSToken();
    }

    _token = await messaging.getToken();
    if (_token != null) {
      await _upsertToken(_token!);
    }

    messaging.onTokenRefresh.listen((token) async {
      _token = token;
      await _upsertToken(token);
    });

    FirebaseMessaging.onMessage.listen(_showForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpen);

    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleOpen(initial);
      });
    }

    Supabase.instance.client.auth.onAuthStateChange.listen((event) async {
      if (event.event == AuthChangeEvent.signedIn) {
        final t = _token ?? await FirebaseMessaging.instance.getToken();
        if (t != null) await _upsertToken(t);
        await requestDrain();
      } else if (event.event == AuthChangeEvent.signedOut) {
        await unregister();
      }
    });

    _ready = true;
    unawaited(requestDrain());
  }

  /// Flushes pending server push jobs (uses SECURITY DEFINER RPC).
  Future<void> requestDrain() async {
    if (Supabase.instance.client.auth.currentSession == null) return;
    try {
      await Supabase.instance.client.rpc('request_push_drain');
    } catch (e) {
      debugPrint('[PUSH] request_push_drain: $e');
    }
  }

  Future<void> unregister() async {
    final token = _token;
    if (token == null) return;
    try {
      await Supabase.instance.client.rpc(
        'delete_push_token',
        params: {'p_token': token},
      );
    } catch (e) {
      debugPrint('[PUSH] delete_push_token: $e');
    }
  }

  Future<void> _upsertToken(String token) async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    final platform = Platform.isIOS
        ? 'ios'
        : Platform.isAndroid
            ? 'android'
            : 'web';
    try {
      await Supabase.instance.client.rpc(
        'upsert_push_token',
        params: {'p_token': token, 'p_platform': platform},
      );
    } catch (e) {
      debugPrint('[PUSH] upsert_push_token: $e');
    }
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final n = message.notification;
    final title = n?.title ?? message.data['title'] as String? ?? 'Уведомление';
    final body = n?.body ?? message.data['body'] as String? ?? '';
    final payload = _encodePayload(message.data);

    await _local.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }

  void _handleOpen(RemoteMessage message) {
    final loc = _locationFromData(message.data);
    if (loc != null) onOpenLocation?.call(loc);
    unawaited(_markSeen(message.data));
  }

  Future<void> _markSeen(Map<String, dynamic> data) async {
    final id = data['notification_id']?.toString();
    if (id == null || id.isEmpty) return;
    final kind = data['kind']?.toString() ?? '';
    try {
      final client = Supabase.instance.client;
      if (kind == 'like' || kind == 'match') {
        await client.rpc(
          'mark_dating_notification_seen',
          params: {'p_notification_id': id},
        );
      } else {
        await client.rpc(
          'mark_user_notification_seen',
          params: {'p_id': id},
        );
      }
    } catch (e) {
      debugPrint('[PUSH] mark seen: $e');
    }
  }

  String? _locationFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    final parts = <String, String>{};
    for (final chunk in payload.split('&')) {
      final i = chunk.indexOf('=');
      if (i <= 0) continue;
      parts[chunk.substring(0, i)] = Uri.decodeComponent(chunk.substring(i + 1));
    }
    return _locationFromData(parts);
  }

  String _encodePayload(Map<String, dynamic> data) {
    return data.entries
        .map(
          (e) =>
              '${e.key}=${Uri.encodeComponent(e.value?.toString() ?? '')}',
        )
        .join('&');
  }

  String? _locationFromData(Map<String, dynamic> data) {
    final kind = data['kind']?.toString() ?? '';
    final eventId = data['event_id']?.toString() ?? '';
    final conversationId = data['conversation_id']?.toString() ?? '';

    switch (kind) {
      case 'event_created':
        if (eventId.isNotEmpty) return '/main/games/$eventId';
        return '/main/games';
      case 'chat_message':
        if (conversationId.isNotEmpty) return '/main/chats/$conversationId';
        return '/main/chats';
      case 'like':
        return '/main/profile/dating';
      case 'match':
        if (conversationId.isNotEmpty) return '/main/chats/$conversationId';
        return '/main/profile/dating/matches';
      default:
        return null;
    }
  }
}
