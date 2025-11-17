// lib/screens/call_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:voice_guardian_app/providers/auth_provider.dart';
import 'package:voice_guardian_app/services/api_service.dart';
import 'package:voice_guardian_app/services/call_state_service.dart';
import 'package:voice_guardian_app/services/agora_call_service.dart';
import 'package:voice_guardian_app/services/permission_service.dart';
import 'package:voice_guardian_app/services/transcription_service.dart';

class CallScreen extends StatefulWidget {
  final String channelName;
  final String? peerUsername;
  final String? agoraToken;
  final int uid;
  final bool isIncoming;
  
  const CallScreen({
    super.key,
    required this.channelName,
    this.peerUsername,
    this.agoraToken,
    required this.uid,
    this.isIncoming = false,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final ApiService _apiService = ApiService();
  late final AgoraCallService _agoraService;
  late final CallStateService _callStateService;
  late final AuthProvider _authProvider;
  late final TranscriptionService _transcriptionService;
  String? _lastRephraseText;
  DateTime? _lastRephraseAt;
  static const String _toxicityWarningText =
      'This is disrespectful; you can say it like this instead.';
  Future<void> _audioQueue = Future<void>.value();
  bool _isCoachAudioPlaying = false;

  bool _isConnecting = true;
  bool _hasCallEnded = false;
  DateTime? _connectedAt;
  String _status = "Connecting...";

  @override
  void initState() {
    super.initState();
    _agoraService = Provider.of<AgoraCallService>(context, listen: false);
    _callStateService = Provider.of<CallStateService>(context, listen: false);
    _authProvider = Provider.of<AuthProvider>(context, listen: false);
    _transcriptionService = Provider.of<TranscriptionService>(context, listen: false);

    // Play coach audio when a rephrase arrives
    _transcriptionService.onRephrase = (original, rephrased, toxicity) async {
      debugPrint('CallScreen: Rephrase callback triggered! original="$original" rephrased="$rephrased" toxicity=$toxicity');
      final now = DateTime.now();
      if (_lastRephraseText == rephrased &&
          _lastRephraseAt != null &&
          now.difference(_lastRephraseAt!).inSeconds < 5) {
        debugPrint('CallScreen: Same rephrase seen recently; skipping to avoid overlap');
        return;
      }
      _lastRephraseText = rephrased;
      _lastRephraseAt = now;
      await _requestAndQueueAudio(rephrased, label: 'rephrase');
    };
    _transcriptionService.onToxicDetected = (transcript, toxicity) {
      if (_shouldIgnoreToxicTranscript(transcript)) {
        debugPrint('CallScreen: Skipping toxic transcript because it matches coach audio');
        return;
      }
      debugPrint('CallScreen: Toxic content detected (score=$toxicity) -> "$transcript"');
      _requestAndQueueAudio(_toxicityWarningText, label: 'warning');
    };

    // Listen for remote user leaving
    _agoraService.onRemoteUserLeft = () {
      if (mounted && !_hasCallEnded) {
        debugPrint('CallScreen: Remote user left the call');
        _showCallEndedMessage('${widget.peerUsername} ended the call');
        _endCall();
      }
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _joinChannel();
    });
  }

  Future<void> _joinChannel() async {
    if (!await _ensureMicrophonePermission()) {
      if (mounted) {
        setState(() {
          _status = "Microphone permission required";
          _isConnecting = false;
        });
      }
      return;
    }

    try {
      String token = widget.agoraToken ?? '';
      
      // If no token provided, fetch it
      if (token.isEmpty) {
        setState(() { _status = "Getting access token..."; });
        final response = await _apiService.getAgoraToken(
          token: _authProvider.token!,
          channelName: widget.channelName,
          uid: widget.uid,
        );
        token = response['token'];
      }

      setState(() { _status = "Connecting to call..."; });
      
      await _agoraService.joinChannel(
        token: token,
        channelName: widget.channelName,
        uid: widget.uid,
        username: _authProvider.username,  // For transcription
      );

      if (mounted) {
        setState(() {
          _status = "Connected";
          _isConnecting = false;
          _connectedAt = DateTime.now();
        });
        _callStateService.markConnected();
      }
    } catch (error) {
      debugPrint('CallScreen: Failed to join channel: $error');
      if (mounted) {
        setState(() {
          _status = "Connection failed";
          _isConnecting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to connect: $error')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  Future<bool> _ensureMicrophonePermission() async {
    if (await PermissionService.isMicrophoneGranted()) {
      return true;
    }

    final granted = await PermissionService.requestMicrophone();
    if (granted) {
      return true;
    }

    if (!mounted) {
      return false;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Microphone access is required to join the call.'),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: PermissionService.openAppSettings,
        ),
      ),
    );
    return false;
  }

  Future<void> _requestAndQueueAudio(String text, {required String label}) async {
    try {
      debugPrint('CallScreen: Requesting TTS ($label): "$text"');
      final response = await _apiService.synthesizeTts(
        token: _authProvider.token!,
        text: text,
      );
      debugPrint('CallScreen: TTS response received ($label)');
      final audioB64 = response['audio_mp3_base64'] as String?;
      if (audioB64 != null) {
        debugPrint('CallScreen: Queuing $label audio (${audioB64.length} bytes base64)');
        final playbackFuture = _audioQueue.then((_) => _playQueuedAudio(audioB64, label));
        _audioQueue = playbackFuture.catchError((error) {
          debugPrint('CallScreen: Audio playback error ($label): $error');
        });
      } else {
        debugPrint('CallScreen: $label TTS response missing audio');
      }
    } catch (e) {
      debugPrint('CallScreen: $label TTS error: $e');
    }
  }

  Future<void> _playQueuedAudio(String audioB64, String label) async {
    try {
      _isCoachAudioPlaying = true;
      debugPrint('CallScreen: Starting queued $label audio');
      await _agoraService.playCoachAudioBase64(audioB64);
    } finally {
      _isCoachAudioPlaying = false;
      debugPrint('CallScreen: Finished queued $label audio');
    }
  }

  bool _shouldIgnoreToxicTranscript(String transcript) {
    if (_isCoachAudioPlaying) return true;
    final lower = transcript.toLowerCase();
    if (lower.contains('you can say it like this instead')) {
      return true;
    }
    if (lower.contains('this is disrespectful')) {
      return true;
    }
    return false;
  }

  Future<void> _endCall() async {
    if (_hasCallEnded) return;
    _hasCallEnded = true;

    try {
      // Leave Agora channel
      await _agoraService.leaveChannel();

      // Report call completion to backend
      if (_connectedAt != null) {
        final duration = DateTime.now().difference(_connectedAt!).inSeconds;
        await _apiService.completeCall(
          token: _authProvider.token!,
          roomName: widget.channelName,
          durationSeconds: duration,
          endedBy: _authProvider.username,
        );
      }

      _callStateService.reset();
    } catch (error) {
      debugPrint('CallScreen: Error ending call: $error');
    }

    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _showCallEndedMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    _agoraService.onRemoteUserLeft = null; // Clear callback
    _transcriptionService.onRephrase = null;
    _transcriptionService.onToxicDetected = null;
    if (!_hasCallEnded) {
      _endCall();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1F2C34),
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _status,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  if (_connectedAt != null) _CallTimer(startTime: _connectedAt!),
                ],
              ),
            ),
            
            // Call info
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.1),
                    ),
                    child: const Icon(
                      Icons.person,
                      size: 60,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    widget.peerUsername ?? 'Unknown',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Consumer<AgoraCallService>(
                    builder: (context, agoraService, _) {
                      if (_isConnecting) {
                        return const Text(
                          'Connecting...',
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        );
                      }
                      if (agoraService.hasRemoteUser) {
                        return const Text(
                          'In call',
                          style: TextStyle(color: Colors.green, fontSize: 16),
                        );
                      }
                      return const Text(
                        'Waiting for other person...',
                        style: TextStyle(color: Colors.orange, fontSize: 16),
                      );
                    },
                  ),
                ],
              ),
            ),
            
            // Control buttons
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Consumer<AgoraCallService>(
                builder: (context, agoraService, _) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Mute button
                      _CallButton(
                        icon: agoraService.isMuted ? Icons.mic_off : Icons.mic,
                        label: agoraService.isMuted ? 'Unmute' : 'Mute',
                        onPressed: agoraService.toggleMute,
                        backgroundColor: agoraService.isMuted
                            ? Colors.white.withOpacity(0.3)
                            : Colors.white.withOpacity(0.1),
                      ),
                      
                      // End call button
                      _CallButton(
                        icon: Icons.call_end,
                        label: 'End',
                        onPressed: _endCall,
                        backgroundColor: Colors.red,
                        size: 72,
                      ),
                      
                      // Speaker button
                      _CallButton(
                        icon: agoraService.isSpeakerOn
                            ? Icons.volume_up
                            : Icons.volume_down,
                        label: agoraService.isSpeakerOn ? 'Speaker' : 'Earpiece',
                        onPressed: agoraService.toggleSpeaker,
                        backgroundColor: agoraService.isSpeakerOn
                            ? Colors.white.withOpacity(0.3)
                            : Colors.white.withOpacity(0.1),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Call button widget
class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final double size;

  const _CallButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.backgroundColor = Colors.white,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onPressed,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: size * 0.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

// Call timer widget
class _CallTimer extends StatefulWidget {
  final DateTime startTime;

  const _CallTimer({required this.startTime});

  @override
  State<_CallTimer> createState() => _CallTimerState();
}

class _CallTimerState extends State<_CallTimer> {
  Timer? _timer;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _duration = DateTime.now().difference(widget.startTime);
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    
    if (duration.inHours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _formatDuration(_duration),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
