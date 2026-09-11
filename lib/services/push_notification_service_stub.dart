/// No-op push on web (FCM / dart:io not available).
class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  void Function(String location)? onOpenLocation;

  bool get isReady => false;

  Future<void> init() async {}

  Future<void> unregister() async {}

  Future<void> requestDrain() async {}
}
