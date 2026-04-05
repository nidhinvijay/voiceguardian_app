// lib/main.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'package:voice_guardian_app/providers/auth_provider.dart';
import 'package:voice_guardian_app/screens/auth_wrapper.dart';
import 'package:voice_guardian_app/screens/incoming_call_screen.dart';

import 'package:voice_guardian_app/services/call_state_service.dart';
import 'package:voice_guardian_app/services/agora_call_service.dart';
import 'package:voice_guardian_app/services/api_service.dart';
import 'package:voice_guardian_app/services/notification_service.dart';
import 'package:voice_guardian_app/services/transcription_service.dart';
import 'package:voice_guardian_app/utils/constants.dart';
import 'firebase_options.dart';

// Global key for navigation from background/terminated states
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Services used across isolates (notification tap + background FCM)
final NotificationService notificationService = NotificationService();

// --- FCM HANDLERS ---
// This function shows our new in-app call screen
// lib/main.dart

// --- NEW FCM HANDLERS ---
// This function shows our new in-app call screen
Future<void> _openIncomingCallUi({
  required String? roomName,
  required String? callerUsername,
  required String callerRespectfulness,
  bool suppressInAppTone = false,
}) async {
  debugPrint('MAIN: Navigating to incoming call UI for $callerUsername');

  NavigatorState? navigator = navigatorKey.currentState;
  BuildContext? context = navigatorKey.currentContext;

  if (navigator == null || context == null) {
    for (var i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 150));
      navigator = navigatorKey.currentState;
      context = navigatorKey.currentContext;
      if (navigator != null && context != null) {
        break;
      }
    }
  }

  if (navigator == null || context == null || !context.mounted) {
    debugPrint('Navigator unavailable, cannot show incoming call UI');
    return;
  }

  await notificationService.clearIncomingCallNotification();

  final callState = Provider.of<CallStateService>(
    context,
    listen: false,
  );
  callState.startRinging(
    roomName: roomName ?? 'unknown',
    peerUsername: callerUsername ?? 'Unknown Caller',
  );

  navigator.push(
    MaterialPageRoute(
      builder: (context) => IncomingCallScreen(
        roomName: roomName ?? 'unknown',
        callerName: callerUsername ?? 'Unknown',
        callerRespectfulness: callerRespectfulness,
        shouldPlayRingtone: !suppressInAppTone,
      ),
    ),
  );
}

void _showIncomingCallScreen(
  RemoteMessage message, {
  bool suppressInAppTone = false,
}) {
  if (message.data['type'] != 'incoming_call') {
    return;
  }
  debugPrint('FCM: incoming_call payload => ${message.data}');
  final callerUsername = message.data['caller_name'];
  final callerRespectfulness = (message.data['caller_respectfulness'] ?? '0').toString();
  final roomName = message.data['room_name'];

  unawaited(
    _openIncomingCallUi(
      roomName: roomName,
      callerUsername: callerUsername,
      callerRespectfulness: callerRespectfulness,
      suppressInAppTone: suppressInAppTone,
    ),
  );
}

Future<bool> _handleCallSignal(RemoteMessage message) async {
  final type = message.data['type'];
  debugPrint('FCM: Handling call signal type=$type payload=${message.data}');
  if (type == 'call_cancelled' || type == 'call_declined') {
    final navigator = navigatorKey.currentState;
    final context = navigatorKey.currentContext;
    await notificationService.clearIncomingCallNotification();
    final actor = message.data['cancelled_by'] ??
        message.data['declined_by'] ??
        (type == 'call_declined' ? 'The other participant' : 'The caller');
    final reason = type == 'call_declined' ? 'declined the call.' : 'cancelled the call.';

    if (navigator != null && navigator.mounted && navigator.canPop()) {
      navigator.pop();
    }
    if (context != null && context.mounted) {
      final callState = Provider.of<CallStateService>(context, listen: false);
      callState.markEnded(endedBy: actor);
      callState.reset();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$actor $reason')),
      );
    }
    return true;
  }
  debugPrint('MAIN: Call signal $type ignored/no action taken.');
  return false;
}

Future<void> _handleNotificationTap(
  Map<String, dynamic> payload,
  String? actionId,
) async {
  BuildContext? context = navigatorKey.currentContext;
  if (context == null) {
    await Future.delayed(const Duration(milliseconds: 300));
    context = navigatorKey.currentContext;
  }
  final type = payload['type'];
  if (type != 'incoming_call') {
    return;
  }

  final callerUsername = payload['caller_name'] as String?;
  final callerRespectfulness =
      (payload['caller_respectfulness'] ?? '0').toString();
  final roomName = payload['room_name'] as String?;

  if (actionId == 'decline_call') {
    debugPrint('Notification action: decline_call');
    if (context != null && context.mounted) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final token = auth.token;
      if (token != null && roomName != null && callerUsername != null) {
        try {
          await ApiService().declineCall(
            token: token,
            roomName: roomName,
            callerUsername: callerUsername,
          );
        } catch (error) {
          debugPrint('Failed to decline call from notification: $error');
        }
      }

      if (!context.mounted) {
        await notificationService.clearIncomingCallNotification();
        return;
      }

      final callState =
          Provider.of<CallStateService>(context, listen: false);
      callState.markEnded(endedBy: callerUsername);
      callState.reset();
    }
    await notificationService.clearIncomingCallNotification();
    return;
  }

  // Default (tap or accept)
  await _openIncomingCallUi(
    roomName: roomName,
    callerUsername: callerUsername,
    callerRespectfulness: callerRespectfulness,
    suppressInAppTone: true,
  );
}

// Foreground message handler
Future<void> _handleForegroundMessage(RemoteMessage message) async {
  debugPrint('FCM: Got a message whilst in the foreground!');
  if (await _handleCallSignal(message)) {
    debugPrint('FCM: Foreground message handled as cancel/decline');
    return;
  }
  if (message.data['type'] == 'incoming_call') {
    await notificationService.showIncomingCallNotification(
      callerName: message.data['caller_name'] ?? 'Unknown',
      roomName: message.data['room_name'] ?? 'unknown',
      callerRespectfulness:
          (message.data['caller_respectfulness'] ?? '0').toString(),
    );
  }
  debugPrint('FCM: Foreground message routed to _showIncomingCallScreen');
  _showIncomingCallScreen(message, suppressInAppTone: true);
}


@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    } on FirebaseException catch (e) {
      if (e.code != 'duplicate-app') rethrow;
    }
  }
  debugPrint("FCM: Handling a background message: ${message.messageId}");
  // We can't navigate from a background isolate,
  // but the FCM notification itself will wake the app.
  // When the user taps the notification, the app will open.
  // We'll handle that logic later (it's called "notification tapping").

  // For now, let's just show our in-app screen if the app is woken up
  // This is a simplification; proper background handling is more complex
  // but _showIncomingCallScreen *might* work if the app is brought to life.
  // Let's just log it for now.
  debugPrint("Background message received: ${message.data}");
  // _showIncomingCallScreen(message); // This line is complex from background, let's simplify
  final type = message.data['type'];
  if (type == 'incoming_call') {
    await notificationService.init();
    await notificationService.showIncomingCallNotification(
      callerName: message.data['caller_name'] ?? 'Unknown',
      roomName: message.data['room_name'] ?? 'unknown',
      callerRespectfulness:
          (message.data['caller_respectfulness'] ?? '0').toString(),
    );
  } else if (type == 'call_cancelled' || type == 'call_declined') {
    await notificationService.init();
    await notificationService.clearIncomingCallNotification();
  }
}
// --- END FCM Handlers ---

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    } on FirebaseException catch (e) {
      if (e.code != 'duplicate-app') rethrow;
    }
  }
  await FirebaseMessaging.instance.requestPermission();
  await notificationService.init(onNotificationTap: _handleNotificationTap);
  FirebaseMessaging.onMessage.listen((message) {
    unawaited(_handleForegroundMessage(message));
  });
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
  // Initialize Agora (create instance early so it's ready)
  final agoraService = AgoraCallService();
  await agoraService.initialize(Constants.agoraAppId);
  
  // Initialize Transcription Service
  final transcriptionService = TranscriptionService();
  agoraService.setTranscriptionService(transcriptionService);
  
  runApp(MyApp(
    agoraService: agoraService,
    transcriptionService: transcriptionService,
  ));
}

class MyApp extends StatefulWidget {
  final AgoraCallService agoraService;
  final TranscriptionService transcriptionService;
  
  const MyApp({
    super.key,
    required this.agoraService,
    required this.transcriptionService,
  });
  @override
  State<MyApp> createState() => _MyAppState();
}

// lib/main.dart

class _MyAppState extends State<MyApp> {

  @override
  void initState() {
    super.initState();
    debugPrint("MyApp initState: Ready for FCM messages.");

    // Handles app opening from terminated state
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) async {
      if (message != null && message.data['type'] == 'incoming_call') {
        debugPrint("App opened from terminated state by notification!");
        final handled = await _handleCallSignal(message);
        debugPrint('InitialMessage handler -> handled=$handled');
        if (!handled) {
          _showIncomingCallScreen(message);
        }
      }
    });

    // Handles app opening from background state
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      debugPrint("App opened from background by notification!");
      final handled = await _handleCallSignal(message);
      debugPrint('onMessageOpenedApp handler -> handled=$handled');
      if (!handled) {
        _showIncomingCallScreen(message);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CallStateService()),
        ChangeNotifierProvider.value(value: widget.agoraService),
        ChangeNotifierProvider.value(value: widget.transcriptionService),
      ],
      child: MaterialApp(
        title: 'VoiceGuardian',
        navigatorKey: navigatorKey, // Assign the global key
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2AABEE),
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xFFF4F7FB),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Color(0xFF1F2C34),
            elevation: 0,
            surfaceTintColor: Colors.white,
          ),
          cardTheme: CardThemeData(
            color: Colors.white,
            surfaceTintColor: Colors.white,
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          bottomNavigationBarTheme: const BottomNavigationBarThemeData(
            backgroundColor: Colors.white,
            selectedItemColor: Color(0xFF2AABEE),
            unselectedItemColor: Color(0xFF96A4AF),
            showUnselectedLabels: true,
          ),
          textTheme: ThemeData.light().textTheme.apply(
                bodyColor: const Color(0xFF1F2C34),
                displayColor: const Color(0xFF1F2C34),
              ),
        ),
        home: const AuthWrapper(),
      ),
    );
  }
}
