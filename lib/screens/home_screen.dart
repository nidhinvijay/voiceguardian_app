// lib/screens/home_screen.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:voice_guardian_app/providers/auth_provider.dart';
import 'package:voice_guardian_app/services/api_service.dart';
import 'package:voice_guardian_app/screens/call_screen.dart';
import 'package:voice_guardian_app/utils/respectfulness_utils.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key, this.refreshTrigger});

  final ValueListenable<int>? refreshTrigger;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final ApiService _apiService = ApiService();
  Future<List<dynamic>>? _friendsFuture;
  ValueListenable<int>? _externalRefreshTrigger;
  VoidCallback? _externalRefreshListener;

  @override
  void initState() {
    super.initState();
    _attachExternalRefresh(widget.refreshTrigger);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authProvider = Provider.of<AuthProvider>(context);
    _friendsFuture ??= authProvider.token != null
        ? _apiService.getFriends(token: authProvider.token!)
        : Future.value(<dynamic>[]);
  }

  Future<void> _refreshFriends() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.token == null) {
      setState(() {
        _friendsFuture = Future.value(<dynamic>[]);
      });
      return;
    }
    final newFuture = _apiService.getFriends(token: authProvider.token!);
    setState(() {
      _friendsFuture = newFuture;
    });
    await newFuture;
  }

  void _attachExternalRefresh(ValueListenable<int>? listenable) {
    _detachExternalRefresh();
    if (listenable == null) {
      return;
    }
    _externalRefreshTrigger = listenable;
    _externalRefreshListener = () {
      unawaited(_refreshFriends());
    };
    listenable.addListener(_externalRefreshListener!);
  }

  void _detachExternalRefresh() {
    final trigger = _externalRefreshTrigger;
    final listener = _externalRefreshListener;
    if (trigger != null && listener != null) {
      trigger.removeListener(listener);
    }
    _externalRefreshTrigger = null;
    _externalRefreshListener = null;
  }

  void _registerCallerNames(List<dynamic> friends) {
    // Placeholder for future registration logic
  }

  @override
  void didUpdateWidget(covariant HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTrigger != widget.refreshTrigger) {
      _attachExternalRefresh(widget.refreshTrigger);
    }
  }

  @override
  void dispose() {
    _detachExternalRefresh();
    super.dispose();
  }

  // --- CALL-STARTING LOGIC ---
  Future<void> _startCall(String friendUsername) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to place a call.')),
      );
      return;
    }

    if (!mounted) return;
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        title: Text("Calling..."),
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text("Connecting..."),
          ],
        ),
      ),
    );

    try {
      // Initiate call via backend
      final response = await _apiService.initiateCall(
        token: authProvider.token!,
        calleeUsername: friendUsername,
      );
      
      final roomName = response['room_name'];
      
      // Generate UID from username hash
      final uid = authProvider.username.hashCode.abs();
      
      // Get Agora token
      final tokenResponse = await _apiService.getAgoraToken(
        token: authProvider.token!,
        channelName: roomName,
        uid: uid,
      );
      final agoraToken = tokenResponse['token'];
      
      // Dismiss loading dialog
      if (navigator.canPop()) {
        navigator.pop();
      }
      
      // Navigate to call screen
      if (mounted) {
        navigator.push(
          MaterialPageRoute(
            builder: (context) => CallScreen(
              channelName: roomName,
              peerUsername: friendUsername,
              agoraToken: agoraToken,
              uid: uid,
              isIncoming: false,
            ),
          ),
        );
      }
    } catch (e) {
      // Dismiss loading dialog
      if (navigator.canPop()) {
        navigator.pop();
      }
      
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text("Error starting call: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final future = _friendsFuture;

    if (authProvider.token == null) {
      return Center(
        child: Text(
          'Log in to see your friends list.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
    }

    if (future == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final listContent = RefreshIndicator(
      onRefresh: _refreshFriends,
      child: FutureBuilder<List<dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 240),
                Center(child: CircularProgressIndicator()),
              ],
            );
          }

          if (snapshot.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 160),
                Center(
                  child: Text(
                    'Unable to load friends.\nPull to refresh.',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            );
          }

          final friends = snapshot.data ?? [];
          if (friends.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: 160),
                Center(
                  child: Text(
                    'You have no friends yet.\nHead to the Friends tab to send requests.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            );
          }

          _registerCallerNames(friends);
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: friends.length,
            itemBuilder: (context, index) {
              final friend = friends[index];
              final friendData = friend['friend'] as Map<String, dynamic>;
              final respectfulnessRaw = friendData['respectfulness_score'];
              final respectfulnessValue = respectfulnessRaw is num
                  ? respectfulnessRaw.toDouble()
                  : double.tryParse(respectfulnessRaw?.toString() ?? '') ?? 0.0;
              final grade = respectfulnessGrade(respectfulnessValue);

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    child: Text(friendData['username'][0].toUpperCase()),
                  ),
                  title: Text(friendData['username']),
                  subtitle: Text(
                    'Respectfulness: $grade',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.call, color: Colors.green),
                    onPressed: () => _startCall(friendData['username']),
                  ),
                ),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(height: 8),
          );
        },
      ),
    );

    return listContent;
  }
}
