// lib/screens/friends_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:voice_guardian_app/providers/auth_provider.dart';
import 'package:voice_guardian_app/services/api_service.dart';
import 'package:voice_guardian_app/utils/phone_utils.dart';

class FriendsTab extends StatefulWidget {
  const FriendsTab({super.key});

  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab> {
  final ApiService _apiService = ApiService();
  bool _isSyncing = false;
  String? _statusMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  Future<void> _syncContacts() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final token = auth.token;
    if (token == null) {
      setState(() {
        _statusMessage = 'Log in to sync your contacts.';
      });
      return;
    }

    final hasPermission = await FlutterContacts.requestPermission(readonly: true);
    if (!hasPermission) {
      setState(() {
        _statusMessage = 'Contacts permission is required to sync your friends list.';
      });
      return;
    }

    setState(() {
      _isSyncing = true;
      _statusMessage = null;
    });

    try {
      final deviceContacts = await FlutterContacts.getContacts(withProperties: true);
      final normalizedMap = <String, String>{};
      for (final contact in deviceContacts) {
        final displayName = contact.displayName.trim();
        for (final phone in contact.phones) {
          final raw = phone.number;
          final normalized = normalizePhoneNumber(raw);
          if (normalized.isEmpty) continue;
          normalizedMap.putIfAbsent(normalized, () => displayName.isNotEmpty ? displayName : normalized);
        }
      }

      final numbers = normalizedMap.keys.toList();
      final matches = numbers.isEmpty
          ? <Map<String, dynamic>>[]
          : await _apiService.matchContacts(token: token, phoneNumbers: numbers);
      final matchByPhone = <String, Map<String, dynamic>>{};
      for (final match in matches) {
        final phone = match['phone_number'];
        if (phone is String) {
          matchByPhone[phone] = match;
        }
      }

      final synced = normalizedMap.entries.map((entry) {
        final match = matchByPhone[entry.key];
        return SyncedContact(
          displayName: entry.value,
          phoneNumber: entry.key,
          username: match?['username'] as String?,
          respectfulness: match?['respectfulness_score'] is num
              ? (match?['respectfulness_score'] as num).toDouble()
              : 0.0,
        );
      }).toList();

      auth.updateSyncedContacts(synced);
      setState(() {
        _statusMessage =
            'Synced ${synced.length} contacts; ${matches.length} are on VoiceGuardian.';
      });
    } catch (error) {
      setState(() {
        _statusMessage = 'Failed to sync contacts: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  Future<void> _launchSmsInvite(String phoneNumber) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = 'Let\'s call on Voiceguardian! It\'s fast, simple and secure. Link : https://earthminorrights.com/';
    final uri = Uri(
      scheme: 'sms',
      path: phoneNumber,
      queryParameters: {'body': message},
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the SMS composer.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final registered = auth.registeredContacts;
    final others = auth.otherContacts;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ElevatedButton.icon(
          onPressed: _isSyncing ? null : _syncContacts,
          icon: _isSyncing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
          label: const Text('Sync Contacts'),
        ),
        if (_statusMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            _statusMessage!,
            style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
                .copyWith(color: Theme.of(context).colorScheme.primary),
          ),
        ],
        const SizedBox(height: 24),
        if (registered.isNotEmpty) ...[
          Text('Contacts on VoiceGuardian', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...registered.map((contact) => ListTile(
                leading: CircleAvatar(
                  child: Text(contact.displayName.isNotEmpty
                      ? contact.displayName[0].toUpperCase()
                      : '?'),
                ),
                title: Text(contact.displayName),
                subtitle: Text('${contact.username} • ${contact.phoneNumber}'),
              )),
          const SizedBox(height: 24),
        ],
        if (others.isNotEmpty) ...[
          Text('Other contacts', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
        ...others.map((contact) {
                return ListTile(
                  leading: const Icon(Icons.contact_phone_outlined),
                  title: Text(contact.displayName),
                  subtitle: Text(contact.phoneNumber),
                  trailing: IconButton(
                    icon: Icon(
                      Icons.sms,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    tooltip: 'Invite via SMS',
                    onPressed: () => _launchSmsInvite(contact.phoneNumber),
                  ),
                );
              }),
        ],
        if (registered.isEmpty && others.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              'Tap Sync Contacts to find which of your contacts use VoiceGuardian. Others will stay listed here for reference.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
      ],
    );
  }
}
