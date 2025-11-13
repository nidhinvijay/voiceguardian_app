// lib/providers/auth_provider.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_guardian_app/services/api_service.dart';
import 'package:voice_guardian_app/services/fcm_service.dart';

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final FcmService _fcmService = FcmService();
  String? _token;
  String? _username;
  StreamSubscription<String>? _tokenRefreshSubscription;

  String? get token => _token;
  String? get username => _username;
  bool get isLoggedIn => _token != null;

  AuthProvider() {
    _loadToken(); // Try to load token on app start
  }

  // Load token from device storage
  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    _username = prefs.getString('username');
    if (_token != null) {
      debugPrint("Token loaded from storage!");
      await _registerDeviceToken();
      _startTokenRefreshListener();
      notifyListeners();
    }
  }

  // Save token to device storage
  Future<void> _saveToken(String token, String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('username', username);
    _token = token;
    _username = username;

    await _registerDeviceToken();
    _startTokenRefreshListener();

    notifyListeners();
  }

  Future<void> _registerDeviceToken() async {
    final authToken = _token;
    if (authToken == null) {
      return;
    }

    try {
      String? fcmToken = await _fcmService.getFcmToken();

      if (fcmToken == null) {
        debugPrint("FCM Token was null, retrying in 2 seconds...");
        await Future.delayed(const Duration(seconds: 2));
        fcmToken = await _fcmService.getFcmToken();
      }

      if (fcmToken == null) {
        debugPrint("FATAL: Could not get FCM token. Device cannot receive calls.");
        return;
      }

      debugPrint("Registering new FCM token: $fcmToken");
      await _apiService.registerDeviceToken(token: authToken, fcmToken: fcmToken);
      debugPrint("FCM Token registered with backend!");
    } catch (e) {
      debugPrint("Failed to register FCM token: $e");
    }
  }

  void _startTokenRefreshListener() {
    if (_token == null) {
      return;
    }

    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = _fcmService.listenForTokenRefresh(
      (newToken) async {
        final authToken = _token;
        if (authToken == null) {
          return;
        }

        debugPrint("FCM token refreshed. Registering new token with backend.");
        try {
          await _apiService.registerDeviceToken(token: authToken, fcmToken: newToken);
          debugPrint("Refreshed FCM token registered with backend!");
        } catch (e) {
          debugPrint("Failed to register refreshed FCM token: $e");
        }
      },
    );
  }

  void _stopTokenRefreshListener() {
    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
  }

  // Login function
  Future<void> login(String username, String password) async {
    try {
      final response = await _apiService.loginUser(
        username: username,
        password: password,
      );
      await _saveToken(response['access_token'], username);
    } catch (e) {
      rethrow; // Re-throw the error to the UI
    }
  }

  // Register function
  Future<void> register(
      String username, String phoneNumber, String password) async {
    try {
      await _apiService.registerUser(
        username: username,
        phoneNumber: phoneNumber,
        password: password,
      );
      // After registering, log them in automatically
      await login(username, password);
    } catch (e) {
      rethrow;
    }
  }

  // Logout function
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('username');
    _stopTokenRefreshListener();
    _token = null;
    _username = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopTokenRefreshListener();
    super.dispose();
  }
}
