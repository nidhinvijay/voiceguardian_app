import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:voice_guardian_app/utils/constants.dart';

class TranscriptionMessage {
  final String type;
  final String? text;
  final bool? isToxic;
  final double? toxicityScore;
  final String? original;
  final String? rephrased;

  TranscriptionMessage({
    required this.type,
    this.text,
    this.isToxic,
    this.toxicityScore,
    this.original,
    this.rephrased,
  });

  factory TranscriptionMessage.fromJson(Map<String, dynamic> json) {
    return TranscriptionMessage(
      type: json['type'] as String,
      text: json['text'] as String?,
      isToxic: json['is_toxic'] as bool?,
      toxicityScore: json['toxicity_score'] != null 
          ? (json['toxicity_score'] as num).toDouble()
          : null,
      original: json['original'] as String?,
      rephrased: json['rephrased'] as String?,
    );
  }
}

class TranscriptionService extends ChangeNotifier {
  WebSocketChannel? _channel;
  bool _isConnected = false;
  String? _currentTranscript;
  String? _latestRephrase;
  String? _latestOriginal;
  double? _latestToxicityScore;
  
  Function(String transcript)? onTranscript;
  Function(String original, String rephrased, double toxicity)? onRephrase;
  Function(String interim)? onInterim;
  
  bool get isConnected => _isConnected;
  String? get currentTranscript => _currentTranscript;
  String? get latestRephrase => _latestRephrase;
  String? get latestOriginal => _latestOriginal;
  double? get latestToxicityScore => _latestToxicityScore;
  
  Future<void> connect({
    required String channelName,
    required String username,
  }) async {
    try {
      final baseUrl = Constants.baseUrl;
      final uri = Uri.parse(baseUrl);
      final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
      final wsUrl = '$wsScheme://${uri.host}:${uri.port}/api/v1/calls/transcribe_audio';
      debugPrint('TranscriptionService: Connecting to $wsUrl');
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel!.stream.listen(
        (message) {
          _handleMessage(message);
        },
        onError: (error) {
          debugPrint('TranscriptionService: WebSocket error: $error');
          _isConnected = false;
          notifyListeners();
        },
        onDone: () {
          debugPrint('TranscriptionService: WebSocket closed');
          _isConnected = false;
          notifyListeners();
        },
      );
      _channel!.sink.add(jsonEncode({
        'type': 'start',
        'channel_name': channelName,
        'username': username,
      }));
      _isConnected = true;
      notifyListeners();
      debugPrint('TranscriptionService: Connected successfully');
    } catch (e) {
      debugPrint('TranscriptionService: Failed to connect: $e');
      _isConnected = false;
      notifyListeners();
    }
  }
  
  void sendAudio(Uint8List audioData) {
    if (!_isConnected || _channel == null) {
      return;
    }
    try {
      final base64Audio = base64Encode(audioData);
      _channel!.sink.add(jsonEncode({
        'type': 'audio',
        'data': base64Audio,
      }));
    } catch (e) {
      debugPrint('TranscriptionService: Failed to send audio: $e');
    }
  }
  
  Future<void> stop() async {
    if (!_isConnected || _channel == null) {
      return;
    }
    try {
      _channel!.sink.add(jsonEncode({'type': 'stop'}));
      await Future.delayed(const Duration(milliseconds: 100));
      await _channel!.sink.close();
      _isConnected = false;
      notifyListeners();
      debugPrint('TranscriptionService: Stopped');
    } catch (e) {
      debugPrint('TranscriptionService: Error stopping: $e');
    }
  }
  
  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final msg = TranscriptionMessage.fromJson(data);
      switch (msg.type) {
        case 'ready':
          debugPrint('TranscriptionService: Ready to receive audio');
          break;
        case 'transcript':
          _currentTranscript = msg.text;
          if (msg.text != null && onTranscript != null) {
            onTranscript!(msg.text!);
          }
          notifyListeners();
          debugPrint('TranscriptionService: Transcript: ${msg.text}');
          break;
        case 'rephrase':
          _latestOriginal = msg.original;
          _latestRephrase = msg.rephrased;
          _latestToxicityScore = msg.toxicityScore;
          debugPrint('TranscriptionService: Rephrase received - original="${msg.original}" rephrased="${msg.rephrased}" toxicity=${msg.toxicityScore}');
          if (msg.original != null && msg.rephrased != null && msg.toxicityScore != null && onRephrase != null) {
            onRephrase!(msg.original!, msg.rephrased!, msg.toxicityScore!);
          }
          notifyListeners();
          break;
        case 'interim':
          if (msg.text != null && onInterim != null) {
            onInterim!(msg.text!);
          }
          debugPrint('TranscriptionService: Interim: ${msg.text}');
          break;
        case 'error':
          debugPrint('TranscriptionService: Error from server: ${msg.text}');
          break;
        case 'stopped':
          debugPrint('TranscriptionService: Transcription stopped');
          break;
      }
    } catch (e) {
      debugPrint('TranscriptionService: Error handling message: $e');
    }
  }
  
  void reset() {
    _currentTranscript = null;
    _latestRephrase = null;
    _latestOriginal = null;
    _latestToxicityScore = null;
    notifyListeners();
  }
  
  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
