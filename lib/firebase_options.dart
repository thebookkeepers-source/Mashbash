import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Mashbash is configured as an Android application.');
    }
    return android;
  }

  static const android = FirebaseOptions(
    apiKey: String.fromEnvironment('FIREBASE_API_KEY', defaultValue: 'configure-me'),
    appId: String.fromEnvironment('FIREBASE_APP_ID', defaultValue: '1:000000000000:android:configure-me'),
    messagingSenderId: String.fromEnvironment('FIREBASE_SENDER_ID', defaultValue: '000000000000'),
    projectId: String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'mashbash-app'),
    storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET', defaultValue: 'mashbash-app.firebasestorage.app'),
  );
}
