// lib/screens/friends_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:voice_guardian_app/providers/auth_provider.dart';
import 'package:voice_guardian_app/services/api_service.dart';

class FriendsTab extends StatefulWidget {
  const FriendsTab({super.key, this.onFriendshipChanged});

  final VoidCallback? onFriendshipChanged;

  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab> {
  final ApiService _apiService = ApiService();
  final TextEditingController _usernameController = TextEditingController();
  Future<List<dynamic>>? _pendingRequestsFuture;
  bool _isSendingRequest = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensurePendingRequestsLoaded();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  void _ensurePendingRequestsLoaded() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final token = auth.token;
    if (token == null) {
      setState(() {
        _pendingRequestsFuture = Future.value(<dynamic>[]);
      });
      return;
    }

    _pendingRequestsFuture ??=
        _apiService.getPendingFriendRequests(token: token);
  }

  Future<void> _refreshPendingRequests() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final token = auth.token;
    if (token == null) {
      setState(() {
        _pendingRequestsFuture = Future.value(<dynamic>[]);
      });
      return;
    }

    final future = _apiService.getPendingFriendRequests(token: token);
    setState(() {
      _pendingRequestsFuture = future;
    });
    await future;
    widget.onFriendshipChanged?.call();
  }

  Future<void> _sendFriendRequest() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final token = auth.token;
    final username = _usernameController.text.trim();

    if (token == null) {
      _showSnackBar('Please log in to send friend requests.');
      return;
    }

    if (username.isEmpty) {
      _showSnackBar('Enter a username to send a request.');
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isSendingRequest = true;
    });

    try {
      await _apiService.sendFriendRequest(token: token, username: username);
      if (!mounted) return;
      _usernameController.clear();
      _showSnackBar('Friend request sent to $username.');
    } catch (error) {
      if (!mounted) return;
      _showSnackBar(_mapErrorToMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _isSendingRequest = false;
        });
      }
    }
  }

  Future<void> _acceptFriendRequest(int friendshipId, String friendName) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final token = auth.token;
    if (token == null) {
      _showSnackBar('Please log in to accept friend requests.');
      return;
    }

    try {
      await _apiService.acceptFriendRequest(
        token: token,
        friendshipId: friendshipId,
      );
      if (!mounted) return;
      _showSnackBar('You and $friendName are now friends!');
      await _refreshPendingRequests();
      widget.onFriendshipChanged?.call();
    } catch (error) {
      if (!mounted) return;
      _showSnackBar(_mapErrorToMessage(error));
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _mapErrorToMessage(Object error) {
    final message = error.toString();
    if (message.contains('SocketException')) {
      return 'Network unavailable. Try again later.';
    }
    return message.replaceFirst('Exception:', '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final theme = Theme.of(context);
    final future = _pendingRequestsFuture;

    if (auth.token == null) {
      return Center(
        child: Text(
          'Log in to manage your friends.',
          style: theme.textTheme.titleMedium,
        ),
      );
    }

    if (future == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _refreshPendingRequests,
      child: FutureBuilder<List<dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 200),
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
                    'Unable to load friend requests. Pull to refresh.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            );
          }

          final pendingRequests = snapshot.data ?? <dynamic>[];

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            children: [
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add a friend',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _usernameController,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _sendFriendRequest(),
                        decoration: const InputDecoration(
                          labelText: 'Friend username',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed:
                              _isSendingRequest ? null : _sendFriendRequest,
                          icon: _isSendingRequest
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.person_add_alt_1),
                          label: Text(
                            _isSendingRequest
                                ? 'Sending request...'
                                : 'Send friend request',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Pending requests',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              if (pendingRequests.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'No pending requests. Share your username so friends can find you!',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                ...pendingRequests.map((request) {
                  final friendData =
                      request is Map<String, dynamic> ? request['friend'] : null;
                  final friend =
                      friendData is Map<String, dynamic> ? friendData : <String, dynamic>{};
                  final username = friend['username']?.toString() ?? 'Unknown';
                  final respectRaw = friend['respectfulness_score'];
                  final respectValue = respectRaw is num
                      ? respectRaw.toDouble()
                      : double.tryParse(respectRaw?.toString() ?? '') ?? 0.0;
                  final friendshipId =
                      request is Map<String, dynamic> ? request['id'] as int? : null;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            theme.colorScheme.primary.withValues(alpha: 0.1),
                        child: Text(username[0].toUpperCase()),
                      ),
                      title: Text(username),
                      subtitle: Text(
                        'Respectfulness: ${respectValue.toStringAsFixed(1)}%',
                      ),
                      trailing: ElevatedButton(
                        onPressed: friendshipId == null
                            ? null
                            : () => _acceptFriendRequest(
                                  friendshipId,
                                  username,
                                  ),
                        child: const Text('Accept'),
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}
