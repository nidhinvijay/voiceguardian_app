// lib/providers/auth_provider.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_guardian_app/services/api_service.dart';
import 'package:voice_guardian_app/services/fcm_service.dart';

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final FcmService _fcmService = FcmService();
  String? _token;
  String? _username;
  String? _phoneNumber;
  double _perspectiveThreshold = 0.089;
  StreamSubscription<String>? _tokenRefreshSubscription;
  bool _isInitializing = true;
  String? _fcmWarning;
  List<SyncedContact> _syncedContacts = [];
  static const String _syncedContactsKey = 'synced_contacts';

  String? get token => _token;
  String? get username => _username;
  String? get phoneNumber => _phoneNumber;
  bool get isLoggedIn => _token != null;
  bool get isInitializing => _isInitializing;
  String? get fcmWarning => _fcmWarning;
  List<SyncedContact> get syncedContacts => List.unmodifiable(_syncedContacts);
  List<SyncedContact> get registeredContacts =>
      _syncedContacts.where((contact) => contact.isRegistered).toList();
  List<SyncedContact> get otherContacts =>
      _syncedContacts.where((contact) => !contact.isRegistered).toList();
  double get perspectiveThreshold => _perspectiveThreshold;

  AuthProvider() {
    _loadToken(); // Try to load token on app start
  }

  // Load token from device storage
  Future<void> _loadToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('token');
      _username = prefs.getString('username');
      _restoreSyncedContacts(prefs);
      if (_token != null) {
        debugPrint("Token loaded from storage!");
        await _registerDeviceToken();
        _startTokenRefreshListener();
        await _refreshProfile();
      }
    } catch (error) {
      debugPrint("Failed to load stored token: $error");
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  // Save token to device storage
  Future<void> _saveToken(
    String token,
    String username, {
    Map<String, dynamic>? preloadedProfile,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('username', username);
    _token = token;
    _username = username;

    if (preloadedProfile != null) {
      _applyUserProfile(preloadedProfile);
    }

    await _registerDeviceToken();
    _startTokenRefreshListener();

    if (preloadedProfile == null) {
      await _refreshProfile();
    }

    notifyListeners();
  }

  Future<void> _registerDeviceToken() async {
    final authToken = _token;
    if (authToken == null) {
      debugPrint('AuthProvider: no auth token yet, skipping device registration');
      return;
    }

    _setFcmWarning(null);
    try {
      String? fcmToken = await _fcmService.getFcmToken();

      if (fcmToken == null) {
        debugPrint("FCM Token was null, retrying in 2 seconds...");
        await Future.delayed(const Duration(seconds: 2));
        fcmToken = await _fcmService.getFcmToken();
      }

      if (fcmToken == null) {
        debugPrint("FATAL: Could not get FCM token. Device cannot receive calls.");
        _setFcmWarning(
          'Could not obtain an FCM token. Incoming call alerts will be disabled until you reinstall or update the app.',
        );
        return;
      }

      debugPrint("Registering new FCM token: $fcmToken");
      final response = await _apiService.registerDeviceToken(token: authToken, fcmToken: fcmToken);
      debugPrint("FCM Token registered with backend! response=$response");
      _setFcmWarning(null);
    } catch (e) {
      debugPrint("Failed to register FCM token: $e");
      _setFcmWarning(
        'Could not register your device for call notifications. Please reinstall the app or contact support.',
      );
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

  void clearFcmWarning() {
    if (_fcmWarning != null) {
      _fcmWarning = null;
      notifyListeners();
    }
  }

  void _setFcmWarning(String? message) {
    if (_fcmWarning == message) {
      return;
    }
    _fcmWarning = message;
    notifyListeners();
  }

  void updateSyncedContacts(List<SyncedContact> contacts) {
    _syncedContacts = List.unmodifiable(contacts);
    notifyListeners();
    unawaited(_persistSyncedContacts());
  }

  void clearSyncedContacts() {
    if (_syncedContacts.isEmpty) {
      return;
    }
    _syncedContacts = [];
    notifyListeners();
    unawaited(_clearSyncedContactsCache());
  }

  void _stopTokenRefreshListener() {
    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
  }

  void _applyUserProfile(Map<String, dynamic> data) {
    final usernameFromProfile = data['username']?.toString();
    if (usernameFromProfile != null && usernameFromProfile.isNotEmpty) {
      _username = usernameFromProfile;
    }
    _phoneNumber = data['phone_number']?.toString();
    final perspectiveValue = data['perspective_threshold'];
    if (perspectiveValue is num) {
      _perspectiveThreshold = perspectiveValue.toDouble();
    } else if (perspectiveValue != null) {
      final parsed = double.tryParse(perspectiveValue.toString());
      if (parsed != null) {
        _perspectiveThreshold = parsed;
      }
    }
  }

  Future<void> _refreshProfile() async {
    if (_token == null) return;
    try {
      final profile = await _apiService.getCurrentUser(token: _token!);
      _applyUserProfile(profile);
    } catch (error) {
      debugPrint('AuthProvider: Failed to refresh profile: $error');
    }
  }

  Future<void> guestLogin(String phoneNumber) async {
    try {
      final response = await _apiService.guestLogin(phoneNumber: phoneNumber);
      final token = response['access_token'] as String?;
      final userData = response['user'] as Map<String, dynamic>?;
      if (token == null) {
        throw Exception('Guest login failed');
      }
      final usernameFromPayload = userData?['username']?.toString() ?? phoneNumber;
      await _saveToken(
        token,
        usernameFromPayload,
        preloadedProfile: userData,
      );
    } catch (error) {
      rethrow;
    }
  }

  Future<void> updatePerspectiveThreshold(double threshold) async {
    final token = _token;
    if (token == null) {
      throw Exception('Not authenticated');
    }
    final response = await _apiService.updatePerspectiveThreshold(
      token: token,
      threshold: threshold,
    );
    _applyUserProfile(response);
    notifyListeners();
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
    await prefs.remove(_syncedContactsKey);
    _stopTokenRefreshListener();
    _token = null;
    _username = null;
    _phoneNumber = null;
    _perspectiveThreshold = 0.089;
    clearSyncedContacts();
    notifyListeners();
  }

  void _restoreSyncedContacts(SharedPreferences prefs) {
    final cached = prefs.getString(_syncedContactsKey);
    if (cached == null || cached.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(cached);
      if (decoded is List) {
        final restored = decoded
            .whereType<Map<String, dynamic>>()
            .map(SyncedContact.fromJson)
            .where((c) => c.phoneNumber.isNotEmpty)
            .toList();
        if (restored.isNotEmpty) {
          _syncedContacts = List.unmodifiable(restored);
        }
      }
    } catch (error) {
      debugPrint('AuthProvider: Failed to restore cached contacts: $error');
    }
  }

  Future<void> _persistSyncedContacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded =
          jsonEncode(_syncedContacts.map((c) => c.toJson()).toList());
      await prefs.setString(_syncedContactsKey, encoded);
    } catch (error) {
      debugPrint('AuthProvider: Failed to persist contacts: $error');
    }
  }

  Future<void> _clearSyncedContactsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_syncedContactsKey);
    } catch (error) {
      debugPrint('AuthProvider: Failed to clear contact cache: $error');
    }
  }

  @override
  void dispose() {
    _stopTokenRefreshListener();
    super.dispose();
  }
}

class SyncedContact {
  SyncedContact({
    required this.displayName,
    required this.phoneNumber,
    this.username,
    this.respectfulness,
  });

  final String displayName;
  final String phoneNumber;
  final String? username;
  final double? respectfulness;

  bool get isRegistered => username != null;

  Map<String, dynamic> toJson() => {
        'display_name': displayName,
        'phone_number': phoneNumber,
        'username': username,
        'respectfulness': respectfulness,
      };

  factory SyncedContact.fromJson(Map<String, dynamic> json) {
    return SyncedContact(
      displayName: json['display_name']?.toString() ?? '',
      phoneNumber: json['phone_number']?.toString() ?? '',
      username: json['username']?.toString(),
      respectfulness: json['respectfulness'] is num
          ? (json['respectfulness'] as num).toDouble()
          : double.tryParse(json['respectfulness']?.toString() ?? ''),
    );
  }
}
