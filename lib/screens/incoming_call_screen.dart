// lib/screens/incoming_call_screen.dart

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:voice_guardian_app/providers/auth_provider.dart';
import 'package:voice_guardian_app/services/api_service.dart';
import 'package:voice_guardian_app/services/call_state_service.dart';
import 'package:voice_guardian_app/screens/call_screen.dart';

class IncomingCallScreen extends StatefulWidget {
  final String roomName;
  final String callerName;
  final String callerRespectfulness;

  const IncomingCallScreen({
    super.key,
    required this.roomName,
    required this.callerName,
    required this.callerRespectfulness,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  final ApiService _apiService = ApiService();
  bool _isProcessing = false;
  StreamSubscription<RemoteMessage>? _signalSubscription;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _beginIncomingFlow();
    });
  }

  @override
  void dispose() {
    _signalSubscription?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _beginIncomingFlow() {
    debugPrint('IncomingCallScreen: Showing incoming call from ${widget.callerName}');

    final callStateService = Provider.of<CallStateService>(context, listen: false);
    callStateService.startRinging(
      roomName: widget.roomName,
      peerUsername: widget.callerName,
    );

    // Listen for cancellation signals
    _signalSubscription = FirebaseMessaging.onMessage.listen((message) {
      final data = message.data;
      if (data['type'] == 'call_cancelled' && data['room_name'] == widget.roomName) {
        unawaited(_handleRemoteCancellation());
      }
    });

    // Auto-dismiss after 45 seconds (call timeout)
    _timeoutTimer = Timer(const Duration(seconds: 45), () {
      if (mounted && !_isProcessing) {
        debugPrint('IncomingCallScreen: Call timed out');
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Call timed out')),
        );
      }
    });
  }

  Future<void> _acceptCall() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    _timeoutTimer?.cancel();

    try {
      debugPrint('IncomingCallScreen: User accepted call from ${widget.callerName}');

      final auth = Provider.of<AuthProvider>(context, listen: false);
      final token = auth.token;
      
      if (token == null) {
        throw Exception('Not authenticated');
      }

      // Generate UID from username hash (deterministic)
      final uid = auth.username.hashCode.abs();

      // Call backend to get Agora token
      final response = await _apiService.getAgoraToken(
        token: token,
        channelName: widget.roomName,
        uid: uid,
      );

      final agoraToken = response['token'];
      debugPrint('IncomingCallScreen: Got Agora token, joining channel');

      if (mounted) {
        // Pop incoming call screen
        Navigator.of(context).pop();

        // Navigate to active call screen
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => CallScreen(
              channelName: widget.roomName,
              peerUsername: widget.callerName,
              agoraToken: agoraToken,
              uid: uid,
              isIncoming: true,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error accepting call: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to accept call: $e")),
        );
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _declineCall() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    _timeoutTimer?.cancel();

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final token = auth.token;
      
      if (token != null) {
        await _apiService.declineCall(
          token: token,
          roomName: widget.roomName,
          callerUsername: widget.callerName,
        );
      }
    } catch (error) {
      debugPrint('Failed to notify caller about decline: $error');
    } finally {
      final callStateService = Provider.of<CallStateService>(context, listen: false);
      callStateService.markEnded(endedBy: widget.callerName);
      callStateService.reset();
      
      if (mounted) {
        setState(() => _isProcessing = false);
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _handleRemoteCancellation() async {
    if (!mounted || _isProcessing) return;

    setState(() => _isProcessing = true);
    _timeoutTimer?.cancel();
    
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final callStateService = Provider.of<CallStateService>(context, listen: false);
    
    if (navigator.canPop()) {
      navigator.pop();
    }
    
    messenger.showSnackBar(
      SnackBar(content: Text('${widget.callerName} cancelled the call.')),
    );
    
    callStateService.markEnded(endedBy: widget.callerName);
    callStateService.reset();
  }

  @override
  Widget build(BuildContext context) {
    final respectfulness = double.tryParse(widget.callerRespectfulness) ?? 0.0;
    final isRespectful = respectfulness >= 3.5;

    return Scaffold(
      backgroundColor: const Color(0xFF1F2C34),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            
            // Caller info
            Column(
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
                const Text(
                  'Incoming Call',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.callerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                
                // Respectfulness indicator
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isRespectful
                        ? Colors.green.withOpacity(0.2)
                        : Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isRespectful
                          ? Colors.green
                          : Colors.orange,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isRespectful ? Icons.star : Icons.star_half,
                        color: isRespectful ? Colors.green : Colors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Respectfulness: ${respectfulness.toStringAsFixed(1)}',
                        style: TextStyle(
                          color: isRespectful ? Colors.green : Colors.orange,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const Spacer(),
            
            // Action buttons
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: _isProcessing
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Decline button
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: _declineCall,
                              child: Container(
                                width: 64,
                                height: 64,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.call_end,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Decline',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        
                        // Accept button
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: _acceptCall,
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.call,
                                  color: Colors.white,
                                  size: 36,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Accept',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
