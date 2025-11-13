// lib/services/api_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:voice_guardian_app/utils/constants.dart';

class ApiService {
  // --- USER REGISTRATION ---
  Future<Map<String, dynamic>> registerUser({
    required String username,
    required String phoneNumber,
    required String password,
  }) async {
    final url = Uri.parse('${Constants.baseUrl}/users/register');
    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: json.encode({
        "username": username,
        "phone_number": phoneNumber,
        "password": password,
      }),
    );
    return _handleResponse(response);
  }

  // --- USER LOGIN ---
  Future<Map<String, dynamic>> loginUser({
    required String username,
    required String password,
  }) async {
    final url = Uri.parse('${Constants.baseUrl}/auth/token');
    
    // FastAPI's OAuth2PasswordRequestForm expects form data, not JSON
    final response = await http.post(
      url,
      headers: {"Content-Type": "application/x-www-form-urlencoded"},
      body: {
        "username": username,
        "password": password,
      },
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> registerDeviceToken({
  required String token, // This is our auth token
  required String fcmToken,
}) async {
  final url = Uri.parse('${Constants.baseUrl}/users/register_device');
  final response = await http.post(
    url,
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token", // <-- We need to be authorized
    },
    body: json.encode({
      "fcm_token": fcmToken,
    }),
  );
  return _handleResponse(response);
}

// lib/services/api_service.dart

  // ... (after your registerDeviceToken function)

  // --- GET AGORA RTC TOKEN ---
  Future<Map<String, dynamic>> getAgoraToken({
    required String token, // Auth token
    required String channelName,
    required int uid,
  }) async {
    final url = Uri.parse('${Constants.baseUrl}/calls/agora_token?channel_name=$channelName&uid=$uid');
    final response = await http.get(
      url,
      headers: {
        "Authorization": "Bearer $token",
      },
    );
    return _handleResponse(response);
  }

  // --- INITIATE VIDEO CALL ---
  Future<Map<String, dynamic>> initiateCall({
    required String token,
    required String calleeUsername,
  }) async {
    final url = Uri.parse('${Constants.baseUrl}/calls/initiate');
    final response = await http.post(
      url,
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: json.encode({
        "callee_username": calleeUsername,
      }),
    );
    return _handleResponse(response);
  }

  // --- ACCEPT VIDEO CALL ---
  Future<Map<String, dynamic>> acceptCall({
    required String token,
    required String roomName,
  }) async {
    final url = Uri.parse('${Constants.baseUrl}/calls/accept');
    final response = await http.post(
      url,
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: json.encode({
        "room_name": roomName,
      }),
    );
    return _handleResponse(response);
  }

  // --- NEW: GET FRIENDS LIST ---
  Future<List<dynamic>> getFriends({required String token}) async {
    final url = Uri.parse('${Constants.baseUrl}/friends/list');
    final response = await http.get(
      url,
      headers: {
        "Authorization": "Bearer $token",
      },
    );
    // This will return a List, so we handle it slightly differently
    final body = json.decode(response.body);
    if (response.statusCode == 200) {
      return body as List<dynamic>;
    } else {
      throw Exception(body['detail'] ?? 'Failed to load friends');
    }
  }

  Future<List<dynamic>> getPendingFriendRequests({required String token}) async {
    final url = Uri.parse('${Constants.baseUrl}/friends/pending');
    final response = await http.get(
      url,
      headers: {
        "Authorization": "Bearer $token",
      },
    );

    final body = json.decode(response.body);
    if (response.statusCode == 200) {
      return body as List<dynamic>;
    } else {
      throw Exception(body['detail'] ?? 'Failed to load pending friend requests');
    }
  }

  Future<Map<String, dynamic>> sendFriendRequest({
    required String token,
    required String username,
  }) async {
    final url = Uri.parse('${Constants.baseUrl}/friends/request');
    final response = await http.post(
      url,
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: json.encode({
        "username": username,
      }),
    );

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> acceptFriendRequest({
    required String token,
    required int friendshipId,
  }) async {
    final url = Uri.parse('${Constants.baseUrl}/friends/accept');
    final response = await http.put(
      url,
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: json.encode({
        "friendship_id": friendshipId,
      }),
    );

    return _handleResponse(response);
  }

  // --- TTS: Synthesize coach audio ---
  Future<Map<String, dynamic>> synthesizeTts({
    required String token,
    required String text,
  }) async {
    final url = Uri.parse('${Constants.baseUrl}/calls/tts');
    final response = await http.post(
      url,
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: json.encode({"text": text}),
    );
    return _handleResponse(response);
  }


  Future<Map<String, dynamic>> declineCall({
    required String token,
    required String roomName,
    required String callerUsername,
  }) async {
    final url = Uri.parse('${Constants.baseUrl}/calls/decline');
    final response = await http.post(
      url,
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: json.encode({
        "room_name": roomName,
        "caller_username": callerUsername,
      }),
    );

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> cancelCall({
    required String token,
    required String roomName,
    required String calleeUsername,
  }) async {
    final url = Uri.parse('${Constants.baseUrl}/calls/cancel');
    final response = await http.post(
      url,
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: json.encode({
        "room_name": roomName,
        "callee_username": calleeUsername,
      }),
    );

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> completeCall({
    required String token,
    required String roomName,
    int? durationSeconds,
    String? endedBy,
  }) async {
    final url = Uri.parse('${Constants.baseUrl}/calls/complete');
    final payload = <String, dynamic>{
      "room_name": roomName,
      if (durationSeconds != null) "duration_seconds": durationSeconds,
      if (endedBy != null) "ended_by": endedBy,
    };

    final response = await http.post(
      url,
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: json.encode(payload),
    );

    return _handleResponse(response);
  }

  Future<List<dynamic>> getCallHistory({
    required String token,
    int? limit,
  }) async {
    final queryParameters = <String, String>{
      if (limit != null) 'limit': limit.toString(),
    };
    final url = Uri.parse('${Constants.baseUrl}/calls/history').replace(queryParameters: queryParameters);
    final response = await http.get(
      url,
      headers: {
        "Authorization": "Bearer $token",
      },
    );

    final body = json.decode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (body is List) {
        return body;
      }
      throw Exception('Unexpected response format');
    } else {
      final detail = body is Map<String, dynamic> ? body['detail'] : null;
      throw Exception(detail ?? 'Failed to load call history');
    }
  }

  Future<Map<String, dynamic>> getCurrentUser({required String token}) async {
    final url = Uri.parse('${Constants.baseUrl}/users/me');
    final response = await http.get(
      url,
      headers: {
        "Authorization": "Bearer $token",
      },
    );
    return _handleResponse(response);
  }
 
  
  // --- GENERIC RESPONSE HANDLER ---
  Map<String, dynamic> _handleResponse(http.Response response) {
    final body = json.decode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Success
      return body;
    } else {
      // Failure - throw an error with the message from our backend
      throw Exception(body['detail'] ?? 'An unknown error occurred');
    }
  }
}
