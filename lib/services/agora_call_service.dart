// lib/services/agora_call_service.dart

import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:path_provider/path_provider.dart';
import 'package:voice_guardian_app/services/transcription_service.dart';

class AgoraCallService extends ChangeNotifier {
  RtcEngine? _engine;
  MediaEngine? _mediaEngine;
  AudioFrameObserver? _audioFrameObserver;
  bool _isJoined = false;
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  int? _remoteUid;
  bool _isAudioMixing = false;
  Completer<void>? _audioMixingCompleter;

  static const int _audioSampleRate = 16000;
  static const int _audioSamplesPerCall = 1024;
  
  TranscriptionService? _transcriptionService;
  bool _isTranscribing = false;
  
  Function()? onRemoteUserLeft;
  
  bool get isJoined => _isJoined;
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get hasRemoteUser => _remoteUid != null;
  bool get isAudioMixing => _isAudioMixing;
  bool get isTranscribing => _isTranscribing;
  
  void setTranscriptionService(TranscriptionService service) {
    _transcriptionService = service;
  }

  void _handleAudioFrame(Uint8List buffer) {
    if (!_isTranscribing || _transcriptionService == null || !_transcriptionService!.isConnected) {
      return;
    }
    try {
      final pcmCopy = Uint8List.fromList(buffer);
      _transcriptionService!.sendAudio(pcmCopy);
    } catch (error) {
      debugPrint('AGORA: Failed to forward audio frame: $error');
    }
  }
  
  Future<void> initialize(String appId) async {
    try {
      debugPrint('AGORA: Initializing with appId: $appId');
      _engine = createAgoraRtcEngine();
      await _engine!.initialize(RtcEngineContext(
        appId: appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));
      await _engine!.enableAudio();
      await _engine!.disableVideo();
      await _engine!.setAudioProfile(
        profile: AudioProfileType.audioProfileDefault,
        scenario: AudioScenarioType.audioScenarioGameStreaming,
      );
      await _engine!.setRecordingAudioFrameParameters(
        sampleRate: _audioSampleRate,
        channel: 1,
        mode: RawAudioFrameOpModeType.rawAudioFrameOpModeReadOnly,
        samplesPerCall: _audioSamplesPerCall,
      );
      await _engine!.setMixedAudioFrameParameters(
        sampleRate: _audioSampleRate,
        channel: 1,
        samplesPerCall: _audioSamplesPerCall,
      );
      if (_audioFrameObserver == null) {
        _audioFrameObserver = AudioFrameObserver(
          onMixedAudioFrame: (channelId, audioFrame) {
            final data = audioFrame.buffer;
            if (data == null || data.isEmpty) {
              return;
            }
            _handleAudioFrame(data);
          },
        );
      }
      _mediaEngine ??= _engine!.getMediaEngine();
      try {
        _mediaEngine?.registerAudioFrameObserver(_audioFrameObserver!);
        debugPrint('AGORA: Audio frame observer ready');
      } catch (error) {
        debugPrint('AGORA: Failed to register audio frame observer: $error');
      }
      _engine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            debugPrint('AGORA: Joined channel: ${connection.channelId}');
            _isJoined = true;
            notifyListeners();
          },
          onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
            debugPrint('AGORA: Remote user joined: $remoteUid');
            _remoteUid = remoteUid;
            notifyListeners();
          },
          onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
            debugPrint('AGORA: Remote user offline: $remoteUid, reason: $reason');
            _remoteUid = null;
            notifyListeners();
            if (onRemoteUserLeft != null) {
              onRemoteUserLeft!();
            }
          },
          onLeaveChannel: (RtcConnection connection, RtcStats stats) {
            debugPrint('AGORA: Left channel');
            _isJoined = false;
            _remoteUid = null;
            notifyListeners();
          },
          onAudioMixingStateChanged: (state, reason) {
            final isPlaying = state == AudioMixingStateType.audioMixingStatePlaying;
            _isAudioMixing = isPlaying;
            if (state == AudioMixingStateType.audioMixingStateStopped &&
                _audioMixingCompleter != null &&
                !_audioMixingCompleter!.isCompleted) {
              _audioMixingCompleter!.complete();
              _audioMixingCompleter = null;
            }
            notifyListeners();
          },
        ),
      );
      debugPrint('AGORA: Initialized successfully');
    } catch (error) {
      debugPrint('AGORA: Failed to initialize: $error');
      rethrow;
    }
  }
  
  Future<void> joinChannel({
    required String token,
    required String channelName,
    required int uid,
    String? username,
  }) async {
    try {
      debugPrint('AGORA: Joining channel: $channelName with uid: $uid');
      if (_transcriptionService != null && username != null) {
        await _transcriptionService!.connect(
          channelName: channelName,
          username: username,
        );
        _isTranscribing = true;
        notifyListeners();
      }
      await _engine!.joinChannel(
        token: token,
        channelId: channelName,
        uid: uid,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          autoSubscribeAudio: true,
          publishMicrophoneTrack: true,
          publishCameraTrack: false,
        ),
      );
      debugPrint('AGORA: Join channel request sent');
    } catch (error) {
      debugPrint('AGORA: Failed to join channel: $error');
      rethrow;
    }
  }
  
  Future<void> playCoachAudioBase64(String base64Mp3) async {
    try {
      final bytes = base64Decode(base64Mp3);
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/coach_${DateTime.now().millisecondsSinceEpoch}.mp3';
      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      final previousCompleter = _audioMixingCompleter;
      if (previousCompleter != null && !previousCompleter.isCompleted) {
        await previousCompleter.future;
      }
      _audioMixingCompleter = Completer<void>();
      await _engine!.startAudioMixing(
        filePath: file.path,
        loopback: false,
        cycle: 1,
      );
      debugPrint('AGORA: Coach audio mixing started: ${file.path}');
      if (_audioMixingCompleter != null) {
        await _audioMixingCompleter!.future;
      }
      debugPrint('AGORA: Coach audio mixing completed: ${file.path}');
    } catch (e) {
      debugPrint('AGORA: Failed to play coach audio: $e');
      if (_audioMixingCompleter != null &&
          !_audioMixingCompleter!.isCompleted) {
        _audioMixingCompleter!.complete();
      }
      _audioMixingCompleter = null;
    }
  }
  
  Future<void> toggleMute() async {
    try {
      _isMuted = !_isMuted;
      await _engine!.muteLocalAudioStream(_isMuted);
      debugPrint('AGORA: Mute toggled: $_isMuted');
      notifyListeners();
    } catch (error) {
      debugPrint('AGORA: Failed to toggle mute: $error');
    }
  }
  
  Future<void> toggleSpeaker() async {
    try {
      _isSpeakerOn = !_isSpeakerOn;
      await _engine!.setEnableSpeakerphone(_isSpeakerOn);
      debugPrint('AGORA: Speaker toggled: $_isSpeakerOn');
      notifyListeners();
    } catch (error) {
      debugPrint('AGORA: Failed to toggle speaker: $error');
    }
  }
  
  Future<void> leaveChannel() async {
    try {
      debugPrint('AGORA: Leaving channel');
      if (_isTranscribing && _transcriptionService != null) {
        await _transcriptionService!.stop();
        _isTranscribing = false;
      }
      await _engine!.leaveChannel();
      _isJoined = false;
      _remoteUid = null;
      notifyListeners();
    } catch (error) {
      debugPrint('AGORA: Error leaving channel: $error');
    }
  }
  
  @override
  Future<void> dispose() async {
    try {
      await leaveChannel();
      if (_audioFrameObserver != null) {
        try {
          _mediaEngine?.unregisterAudioFrameObserver(_audioFrameObserver!);
        } catch (error) {
          debugPrint('AGORA: Failed to unregister audio frame observer: $error');
        }
      }
      _mediaEngine = null;
      _audioFrameObserver = null;
      await _engine?.release();
      _engine = null;
    } catch (error) {
      debugPrint('AGORA: Error disposing: $error');
    }
    super.dispose();
  }
}
