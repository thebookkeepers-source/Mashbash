import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../firebase_options.dart';
import '../models/app_models.dart';
import 'supabase_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (DefaultFirebaseOptions.isConfigured) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
}

class NotificationService {
  NotificationService({SupabaseService? data}) : _data = data ?? SupabaseService();

  final SupabaseService _data;
  StreamSubscription<String>? _tokenRefresh;
  StreamSubscription<RemoteMessage>? _openedMessage;
  String? _activeToken;
  void Function(String orderId)? onOrderTap;

  Future<void> initialize() async {
    if (!DefaultFirebaseOptions.isConfigured) return;
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      final messaging = FirebaseMessaging.instance;
      await messaging.setAutoInitEnabled(true);
      _openedMessage = FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
      _tokenRefresh = messaging.onTokenRefresh.listen((token) {
        _activeToken = token;
        _data.saveDeviceToken(token, Platform.isAndroid ? 'android' : Platform.operatingSystem).catchError((_) {});
      });
      final initial = await messaging.getInitialMessage();
      if (initial != null) _handleMessage(initial);
    } catch (_) {
      // Missing or invalid public Firebase config disables FCM without affecting Supabase.
    }
  }

  Future<void> activate(AppUser user) async {
    if (!DefaultFirebaseOptions.isConfigured) return;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      _activeToken = token;
      await _data.saveDeviceToken(token, Platform.isAndroid ? 'android' : Platform.operatingSystem);
    } catch (_) {
      // Notifications are optional and must never block sign-in or app use.
    }
  }

  Future<void> deactivate() async {
    final token = _activeToken;
    _activeToken = null;
    if (token == null) return;
    try {
      await _data.deactivateDeviceToken(token);
    } catch (_) {
      // Sign-out still proceeds if the server is temporarily unavailable.
    }
  }

  void _handleMessage(RemoteMessage message) {
    final orderId = message.data['order_id'];
    if (orderId is String && orderId.isNotEmpty) onOrderTap?.call(orderId);
  }

  Future<void> dispose() async {
    await _tokenRefresh?.cancel();
    await _openedMessage?.cancel();
  }
}
