import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Filled from `.env` (FlutterFire / Firebase console).
/// Leave empty to disable push until Firebase is connected.
class DefaultFirebaseOptions {
  static bool get isConfigured {
    final id = dotenv.env['FIREBASE_PROJECT_ID']?.trim() ?? '';
    final androidAppId = dotenv.env['FIREBASE_ANDROID_APP_ID']?.trim() ?? '';
    final iosAppId = dotenv.env['FIREBASE_IOS_APP_ID']?.trim() ?? '';
    final apiKey = dotenv.env['FIREBASE_API_KEY']?.trim() ?? '';
    if (id.isEmpty || apiKey.isEmpty) return false;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return iosAppId.isNotEmpty;
    }
    return androidAppId.isNotEmpty;
  }

  static FirebaseOptions get currentPlatform {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return ios;
    }
    return android;
  }

  static FirebaseOptions get android => FirebaseOptions(
        apiKey: dotenv.env['FIREBASE_API_KEY']!.trim(),
        appId: dotenv.env['FIREBASE_ANDROID_APP_ID']!.trim(),
        messagingSenderId:
            (dotenv.env['FIREBASE_MESSAGING_SENDER_ID'] ?? '').trim(),
        projectId: dotenv.env['FIREBASE_PROJECT_ID']!.trim(),
        storageBucket: dotenv.env['FIREBASE_STORAGE_BUCKET']?.trim(),
      );

  static FirebaseOptions get ios => FirebaseOptions(
        apiKey: (dotenv.env['FIREBASE_IOS_API_KEY'] ??
                dotenv.env['FIREBASE_API_KEY']!)
            .trim(),
        appId: dotenv.env['FIREBASE_IOS_APP_ID']!.trim(),
        messagingSenderId:
            (dotenv.env['FIREBASE_MESSAGING_SENDER_ID'] ?? '').trim(),
        projectId: dotenv.env['FIREBASE_PROJECT_ID']!.trim(),
        storageBucket: dotenv.env['FIREBASE_STORAGE_BUCKET']?.trim(),
        iosBundleId:
            (dotenv.env['FIREBASE_IOS_BUNDLE_ID'] ?? 'ru.moystrikbol.app')
                .trim(),
      );
}
