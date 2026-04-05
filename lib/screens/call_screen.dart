// lib/screens/call_screen.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  bool _didWarmupAudio = false;
  String? _lastRephraseText;
  DateTime? _lastRephraseAt;
  String? _lastRephraseAudioUrl;
  DateTime? _lastRephraseAudioAt;
  static const String _warningAssetPath = 'assets/audio/toxicity_warning.wav';
  Uint8List? _warningClipBytes;
  DateTime? _lastWarningAt;
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
      await _handleRephraseEvent(rephrased, audioUrl: null, legacyFallback: true);
    };
    _transcriptionService.onRephraseReady = (text, audioUrl) async {
      debugPrint('CallScreen: Rephrase-ready callback text="$text" audioUrl=$audioUrl');
      await _handleRephraseEvent(text, audioUrl: audioUrl);
    };
    _transcriptionService.onToxicityAlert = () {
      _handleToxicityTrigger('alert');
    };
    _transcriptionService.onToxicDetected = (transcript, toxicity) {
      if (_shouldIgnoreToxicTranscript(transcript)) {
        debugPrint('CallScreen: Skipping toxic transcript because it matches coach audio');
        return;
      }
      _handleToxicityTrigger('transcript');
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
        perspectiveThreshold: _authProvider.perspectiveThreshold,
      );

      if (mounted) {
        setState(() {
          _status = "Connected";
          _isConnecting = false;
          _connectedAt = DateTime.now();
        });
        _callStateService.markConnected();
        // Warm up coach audio once per call to avoid first-playback drop.
        _warmupCoachAudio();
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
        final bytes = base64Decode(audioB64);
        _queueAudioBytes(bytes, label: label, extension: 'mp3');
      } else {
        debugPrint('CallScreen: $label TTS response missing audio');
      }
    } catch (e) {
      debugPrint('CallScreen: $label TTS error: $e');
    }
  }

  Future<void> _handleRephraseEvent(String? rephrasedText, {String? audioUrl, bool legacyFallback = false}) async {
    if (rephrasedText == null || rephrasedText.isEmpty) {
      return;
    }
    if (_shouldSkipRephrase(rephrasedText, audioUrl)) {
      debugPrint('CallScreen: Duplicate rephrase ignored (text="$rephrasedText" audioUrl=$audioUrl)');
      return;
    }
    final now = DateTime.now();
    _lastRephraseText = rephrasedText;
    _lastRephraseAt = now;
    _lastRephraseAudioUrl = audioUrl;
    _lastRephraseAudioAt = audioUrl != null ? now : null;

    if (audioUrl != null) {
      await _queueRemoteRephrase(audioUrl, rephrasedText);
      return;
    }
    if (legacyFallback) {
      await _requestAndQueueAudio(rephrasedText, label: 'rephrase');
    }
  }

  Future<void> _queueRemoteRephrase(String audioUrl, String fallbackText) async {
    try {
      final bytes = await _apiService.downloadAudioFile(
        url: audioUrl,
        token: _authProvider.token,
      );
      final extension = _inferExtensionFromUrl(audioUrl);
      _queueAudioBytes(bytes, label: 'rephrase', extension: extension);
    } catch (error) {
      debugPrint('CallScreen: Failed to download rephrase audio: $error');
      await _requestAndQueueAudio(fallbackText, label: 'rephrase');
    }
  }

  void _queueAudioBytes(Uint8List bytes, {required String label, required String extension}) {
    final playbackFuture = _audioQueue.then((_) async {
      _isCoachAudioPlaying = true;
      debugPrint('CallScreen: Starting queued $label audio');
      try {
        await _agoraService.playCoachAudioBytes(bytes, fileExtension: extension);
      } finally {
        _isCoachAudioPlaying = false;
        debugPrint('CallScreen: Finished queued $label audio');
      }
    });
    _audioQueue = playbackFuture.catchError((error) {
      debugPrint('CallScreen: Audio playback error ($label): $error');
    });
  }

  Future<void> _queueWarningClip() async {
    final bytes = await _loadWarningClipBytes();
    if (bytes == null) {
      return;
    }
    _queueAudioBytes(bytes, label: 'warning', extension: 'wav');
  }

  Future<Uint8List?> _loadWarningClipBytes() async {
    if (_warningClipBytes != null) {
      return _warningClipBytes;
    }
    try {
      final data = await rootBundle.load(_warningAssetPath);
      _warningClipBytes = data.buffer.asUint8List();
      return _warningClipBytes;
    } catch (error) {
      debugPrint('CallScreen: Failed to load warning clip asset: $error');
      return null;
    }
  }

  void _handleToxicityTrigger(String source) {
    final now = DateTime.now();
    if (_lastWarningAt != null &&
        now.difference(_lastWarningAt!).inMilliseconds < 1200) {
      debugPrint('CallScreen: Ignoring $source toxicity trigger due to cooldown');
      return;
    }
    _lastWarningAt = now;
    debugPrint('CallScreen: Toxicity trigger from $source');
    _queueWarningClip();
  }

  String _inferExtensionFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      if (path.contains('.')) {
        return path.split('.').last.toLowerCase();
      }
    } catch (_) {
      // Ignore parse errors and fall back to mp3.
    }
    return 'mp3';
  }

  bool _shouldSkipRephrase(String text, String? audioUrl) {
    final now = DateTime.now();
    final textRecent = _lastRephraseText == text &&
        _lastRephraseAt != null &&
        now.difference(_lastRephraseAt!).inMilliseconds < 4000;
    final audioRecent = audioUrl != null &&
        _lastRephraseAudioUrl == audioUrl &&
        _lastRephraseAudioAt != null &&
        now.difference(_lastRephraseAudioAt!).inMilliseconds < 4000;
    return textRecent || audioRecent;
  }

  bool _shouldIgnoreToxicTranscript(String transcript) {
    if (_isCoachAudioPlaying) return true;
    final lower = transcript.trim().toLowerCase();
    final rephrase = _lastRephraseText?.trim().toLowerCase();
    if (rephrase != null && rephrase.isNotEmpty && lower == rephrase) {
      return true;
    }
    return false;
  }

  Future<void> _warmupCoachAudio() async {
    if (_didWarmupAudio) return;
    _didWarmupAudio = true;
    if (!mounted) return;
    try {
      debugPrint('CallScreen: Warmup loading warning clip');
      await _loadWarningClipBytes();
    } catch (error) {
      debugPrint('CallScreen: Warmup warning clip failed: $error');
    }
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
                      color: Colors.white.withValues(alpha: 0.1),
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
                            ? Colors.white.withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.1),
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
                            ? Colors.white.withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.1),
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
