import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';
import '../models/app_models.dart';
import 'supabase_service.dart';

const mashbashOrdersChannel = AndroidNotificationChannel(
  'mashbash_orders',
  'Mashbash Orders',
  description: 'Order and delivery updates from Mashbash.',
  importance: Importance.high,
);

enum NotificationActivationStatus { active, denied, unavailable, failed }

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (DefaultFirebaseOptions.isConfigured) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } else {
    await Firebase.initializeApp();
  }
}

class NotificationService {
  NotificationService({SupabaseService? data}) : _data = data ?? SupabaseService();

  final SupabaseService _data;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  StreamSubscription<String>? _tokenRefresh;
  StreamSubscription<RemoteMessage>? _openedMessage;
  StreamSubscription<RemoteMessage>? _foregroundMessage;
  AppUser? _activeUser;
  String? _activeToken;
  void Function(String orderId)? onOrderTap;

  Future<void> initialize() async {
    if (Firebase.apps.isEmpty) return;
    try {
      const settings = InitializationSettings(android: AndroidInitializationSettings('mashbash_notification'));
      await _localNotifications.initialize(
        settings,
        onDidReceiveNotificationResponse: (response) => _handleOrderId(response.payload),
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(mashbashOrdersChannel);

      final messaging = FirebaseMessaging.instance;
      await messaging.setAutoInitEnabled(true);
      _foregroundMessage = FirebaseMessaging.onMessage.listen(_showForegroundNotification);
      _openedMessage = FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
      _tokenRefresh = messaging.onTokenRefresh.listen((token) async {
        _activeToken = token;
        if (_activeUser == null) return;
        await _saveToken(token, _activeUser!);
      });

      final localLaunch = await _localNotifications.getNotificationAppLaunchDetails();
      if (localLaunch?.didNotificationLaunchApp == true) {
        _handleOrderId(localLaunch?.notificationResponse?.payload);
      }
      final initial = await messaging.getInitialMessage();
      if (initial != null) _handleMessage(initial);
    } catch (exception) {
      if (kDebugMode) debugPrint('Notification initialization unavailable: ${exception.runtimeType}');
    }
  }

  Future<NotificationActivationStatus> activate(AppUser user) async {
    if (Firebase.apps.isEmpty) return NotificationActivationStatus.unavailable;
    _activeUser = user;
    try {
      final messagingSettings = await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
      final localPermission = await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      if (messagingSettings.authorizationStatus == AuthorizationStatus.denied || localPermission == false) {
        return NotificationActivationStatus.denied;
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return NotificationActivationStatus.unavailable;
      _activeToken = token;
      await _saveToken(token, user);
      return NotificationActivationStatus.active;
    } catch (exception) {
      if (kDebugMode) debugPrint('Notification activation failed for ${user.role.name}: ${exception.runtimeType}');
      return NotificationActivationStatus.failed;
    }
  }

  Future<void> _saveToken(String token, AppUser user) async {
    try {
      await _data.saveDeviceToken(token, Platform.isAndroid ? 'android' : Platform.operatingSystem);
      if (kDebugMode) debugPrint('FCM token registered for ${user.role.name}: ...${token.substring(token.length > 6 ? token.length - 6 : 0)}');
    } catch (exception) {
      if (kDebugMode) debugPrint('FCM token registration failed for ${user.role.name}: ${exception.runtimeType}');
    }
  }

  Future<void> deactivate() async {
    final token = _activeToken;
    _activeUser = null;
    _activeToken = null;
    if (token == null) return;
    try {
      await _data.deactivateDeviceToken(token);
      if (kDebugMode) debugPrint('FCM token marked inactive.');
    } catch (exception) {
      if (kDebugMode) debugPrint('FCM token deactivation failed: ${exception.runtimeType}');
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final title = message.notification?.title ?? message.data['title']?.toString() ?? 'Mashbash order update';
    final body = message.notification?.body ?? message.data['body']?.toString() ?? 'Open Mashbash to view the latest update.';
    final orderId = message.data['order_id']?.toString();
    await _localNotifications.show(
      message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          mashbashOrdersChannel.id,
          mashbashOrdersChannel.name,
          channelDescription: mashbashOrdersChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          color: const Color(0xFF8B0000),
          icon: 'mashbash_notification',
        ),
      ),
      payload: orderId,
    );
  }

  void _handleMessage(RemoteMessage message) => _handleOrderId(message.data['order_id']?.toString());

  void _handleOrderId(String? orderId) {
    if (orderId != null && orderId.isNotEmpty) onOrderTap?.call(orderId);
  }

  Future<void> dispose() async {
    await _tokenRefresh?.cancel();
    await _openedMessage?.cancel();
    await _foregroundMessage?.cancel();
  }
}
