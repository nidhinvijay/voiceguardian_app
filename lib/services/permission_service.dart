// lib/services/permission_service.dart

import 'package:flutter/services.dart';

class PermissionService {
  static const MethodChannel _channel =
      MethodChannel('voice_guardian_app/permissions');

  static Future<bool> isMicrophoneGranted() async {
    final result =
        await _channel.invokeMethod<bool>('checkMicrophonePermission');
    return result ?? false;
  }

  static Future<bool> requestMicrophone() async {
    final result =
        await _channel.invokeMethod<bool>('requestMicrophonePermission');
    return result ?? false;
  }

  static Future<void> openAppSettings() async {
    await _channel.invokeMethod('openAppSettings');
  }
}
