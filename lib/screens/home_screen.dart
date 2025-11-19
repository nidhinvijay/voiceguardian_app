// lib/screens/home_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:voice_guardian_app/providers/auth_provider.dart';
import 'package:voice_guardian_app/screens/call_screen.dart';
import 'package:voice_guardian_app/services/api_service.dart';
import 'package:voice_guardian_app/utils/respectfulness_utils.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final ApiService _apiService = ApiService();

  Future<void> _startCall(SyncedContact contact) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token;
    final username = contact.username;
    if (token == null || username == null) {
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
        title: Text('Calling...'),
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Connecting...'),
          ],
        ),
      ),
    );

    try {
      final response = await _apiService.initiateCall(
        token: token,
        calleeUsername: username,
      );
      final roomName = response['room_name'];
      final uid = authProvider.username.hashCode.abs();

      final tokenResponse = await _apiService.getAgoraToken(
        token: token,
        channelName: roomName,
        uid: uid,
      );
      final agoraToken = tokenResponse['token'];

      if (navigator.canPop()) {
        navigator.pop();
      }

      if (!mounted) return;
      navigator.push(
        MaterialPageRoute(
          builder: (context) => CallScreen(
            channelName: roomName,
            peerUsername: username,
            agoraToken: agoraToken,
            uid: uid,
            isIncoming: false,
          ),
        ),
      );
    } catch (e) {
      if (navigator.canPop()) {
        navigator.pop();
      }
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Error starting call: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    if (authProvider.token == null) {
      return Center(
        child: Text(
          'Log in to view your synced contacts.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
    }

    final contacts = authProvider.registeredContacts;
    if (contacts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Sync your address book on the Friends tab to see who is already on VoiceGuardian.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Open the Friends tab to sync contacts.')),
                  );
                },
                child: const Text('Open Friends Tab'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: contacts.length,
      separatorBuilder: (context, index) => const Divider(height: 16),
      itemBuilder: (context, index) {
        final contact = contacts[index];
        final respectfulnessValue = contact.respectfulness ?? 0.0;
        final grade = respectfulnessGrade(respectfulnessValue);
        return ListTile(
          leading: CircleAvatar(
            child: Text(contact.displayName.isNotEmpty
                ? contact.displayName[0].toUpperCase()
                : '?'),
          ),
          title: Text(contact.displayName),
          subtitle: Text('${contact.username ?? contact.phoneNumber} • $grade'),
          trailing: ElevatedButton(
            onPressed: () => _startCall(contact),
            child: const Text('Call'),
          ),
        );
      },
    );
  }
}
