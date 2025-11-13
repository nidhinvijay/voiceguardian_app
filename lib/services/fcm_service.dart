// lib/services/fcm_service.dart

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

// This function MUST be a top-level function (not in a class)
// to be handled when the app is terminated.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint("Handling a background message: ${message.messageId}");
  debugPrint("Data: ${message.data}");

  // Here, we would show the callkit screen.
  // We'll add this logic in a moment.
}

class FcmService {
  final _firebaseMessaging = FirebaseMessaging.instance;

  Future<void> initNotifications() async {
    // Request permission from the user (for iOS)
    await _firebaseMessaging.requestPermission();

    // Get the unique FCM token for this device
    final fcmToken = await _firebaseMessaging.getToken();
    debugPrint("=================================");
    debugPrint("FCM Token: $fcmToken");
    debugPrint("=================================");

    // Set up handlers
    _initPushHandlers();
  }

  void _initPushHandlers() {
    // Handler for when the app is in the foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a message whilst in the foreground!');
      debugPrint('Data: ${message.data}');

      if (message.data['type'] == 'incoming_call') {
        // We'll show the call screen here
      }
    });

    // Handler for when the app is in the background or terminated
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  /// A helper function to get the current FCM token.
  Future<String?> getFcmToken() async {
    return _firebaseMessaging.getToken();
  }

  /// Listen for token refresh events and forward them to the provided handler.
  StreamSubscription<String> listenForTokenRefresh(
    Future<void> Function(String token) handler,
  ) {
    return _firebaseMessaging.onTokenRefresh.listen(
      (token) {
        try {
          final future = handler(token);
          unawaited(
            future.catchError(
              (error, stackTrace) {
                debugPrint('Failed to process refreshed FCM token: $error');
              },
            ),
          );
        } catch (error) {
          debugPrint('Failed to start processing refreshed FCM token: $error');
        }
      },
      onError: (error) {
        debugPrint('Error listening for token refresh: $error');
      },
    );
  }
}
