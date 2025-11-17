// lib/services/notification_service.dart
//
// Centralized wrapper around flutter_local_notifications to surface
// heads‑up / full‑screen incoming call alerts.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

typedef NotificationTapHandler = Future<void> Function(
  Map<String, dynamic> payload,
  String? actionId,
);

class NotificationService {
  NotificationService._internal();

  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _callChannelId = 'incoming_calls';
  static const int _callNotificationId = 2210;

  /// Initializes the plugin and call notification channel.
  /// Safe to call multiple times (last provided tap handler wins).
  Future<void> init({NotificationTapHandler? onNotificationTap}) async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    final settings = const InitializationSettings(android: androidInit);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) async {
        final payload = response.payload;
        if (payload == null || payload.isEmpty || onNotificationTap == null) {
          return;
        }
        try {
          final decoded = jsonDecode(payload) as Map<String, dynamic>;
          await onNotificationTap(decoded, response.actionId);
        } catch (error) {
          debugPrint('Failed to handle notification tap: $error');
        }
      },
    );

    await _createCallChannel();
  }

  Future<void> _createCallChannel() async {
    const channel = AndroidNotificationChannel(
      _callChannelId,
      'Incoming Calls',
      description: 'VoiceGuardian call alerts',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<void> showIncomingCallNotification({
    required String callerName,
    required String roomName,
    required String callerRespectfulness,
  }) async {
    final payload = jsonEncode({
      'type': 'incoming_call',
      'caller_name': callerName,
      'room_name': roomName,
      'caller_respectfulness': callerRespectfulness,
    });

    const androidDetails = AndroidNotificationDetails(
      _callChannelId,
      'Incoming Calls',
      channelDescription: 'VoiceGuardian incoming call alerts',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      autoCancel: false,
      ongoing: true,
      visibility: NotificationVisibility.public,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'accept_call',
          'Accept',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          'decline_call',
          'Decline',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    await _plugin.show(
      _callNotificationId,
      'Incoming call from $callerName',
      'Tap to answer',
      notificationDetails,
      payload: payload,
    );
  }

  Future<void> clearIncomingCallNotification() async {
    await _plugin.cancel(_callNotificationId);
  }
}
