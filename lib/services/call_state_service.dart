// lib/services/call_state_service.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents the current lifecycle state of a call.
enum CallLifecycleState {
  idle,
  ringing,
  connected,
  ended,
}

/// A centralized service that tracks call state across the app, making it
/// easier to coordinate native Telecom/CallKit actions with Flutter UI and
/// backend updates.
class CallStateService extends ChangeNotifier {
  CallLifecycleState _state = CallLifecycleState.idle;
  String? _roomName;
  String? _peerUsername;
  DateTime? _ringingSince;
  DateTime? _connectedAt;
  String? _endedBy;

  CallLifecycleState get state => _state;
  String? get roomName => _roomName;
  String? get peerUsername => _peerUsername;
  DateTime? get ringingSince => _ringingSince;
  DateTime? get connectedAt => _connectedAt;
  String? get endedBy => _endedBy;

  bool get isIdle => _state == CallLifecycleState.idle;
  bool get isRinging => _state == CallLifecycleState.ringing;
  bool get isConnected => _state == CallLifecycleState.connected;

  final StreamController<CallLifecycleState> _stateStreamController =
      StreamController<CallLifecycleState>.broadcast();

  Stream<CallLifecycleState> get stateStream => _stateStreamController.stream;

  CallStateService() {
    _restoreState();
  }

  void _setState(CallLifecycleState newState) {
    if (_state == newState) {
      return;
    }
    debugPrint('CallStateService: $_state -> $newState (room=$_roomName peer=$_peerUsername)');
    _state = newState;
    _stateStreamController.add(newState);
    notifyListeners();
    _persistState();
  }

  void startRinging({required String roomName, required String peerUsername}) {
    _roomName = roomName;
    _peerUsername = peerUsername;
    _ringingSince = DateTime.now();
    _connectedAt = null;
    _endedBy = null;
    _setState(CallLifecycleState.ringing);
  }

  void markConnected() {
    if (_roomName == null) {
      return;
    }
    _connectedAt = DateTime.now();
    debugPrint('CallStateService: markConnected room=$_roomName');
    _setState(CallLifecycleState.connected);
  }

  void markEnded({String? endedBy}) {
    _endedBy = endedBy;
    debugPrint('CallStateService: markEnded room=$_roomName endedBy=$endedBy');
    _setState(CallLifecycleState.ended);
  }

  void reset() {
    debugPrint('CallStateService: reset()');
    _roomName = null;
    _peerUsername = null;
    _ringingSince = null;
    _connectedAt = null;
    _endedBy = null;
    _setState(CallLifecycleState.idle);
  }

  Future<void> _persistState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_state == CallLifecycleState.idle) {
        await prefs.remove('call_state_room');
        await prefs.remove('call_state_peer');
        await prefs.remove('call_state_status');
        await prefs.remove('call_state_ringing');
        await prefs.remove('call_state_connected');
        await prefs.remove('call_state_ended_by');
        return;
      }

      await prefs.setString('call_state_status', _state.name);
      if (_roomName != null) {
        await prefs.setString('call_state_room', _roomName!);
      }
      if (_peerUsername != null) {
        await prefs.setString('call_state_peer', _peerUsername!);
      }
      if (_ringingSince != null) {
        await prefs.setString('call_state_ringing', _ringingSince!.toIso8601String());
      }
      if (_connectedAt != null) {
        await prefs.setString('call_state_connected', _connectedAt!.toIso8601String());
      }
      if (_endedBy != null) {
        await prefs.setString('call_state_ended_by', _endedBy!);
      }
    } catch (error) {
      debugPrint('Failed to persist call state: $error');
    }
  }

  Future<void> _restoreState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedStatus = prefs.getString('call_state_status');
      if (storedStatus == null) {
        return;
      }

      final mapped = CallLifecycleState.values.firstWhere(
        (value) => value.name == storedStatus,
        orElse: () => CallLifecycleState.idle,
      );

      if (mapped == CallLifecycleState.idle) {
        return;
      }

      _state = mapped;
      _roomName = prefs.getString('call_state_room');
      _peerUsername = prefs.getString('call_state_peer');
      final ringing = prefs.getString('call_state_ringing');
      final connected = prefs.getString('call_state_connected');
      final endedBy = prefs.getString('call_state_ended_by');
      if (ringing != null) {
        _ringingSince = DateTime.tryParse(ringing);
      }
      if (connected != null) {
        _connectedAt = DateTime.tryParse(connected);
      }
      _endedBy = endedBy;

      // Notify listeners about restored state.
      _stateStreamController.add(_state);
      notifyListeners();
    } catch (error) {
      debugPrint('Failed to restore call state: $error');
    }
  }

  @override
  void dispose() {
    _stateStreamController.close();
    super.dispose();
  }
}
