// lib/screens/profile_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:voice_guardian_app/providers/auth_provider.dart';
import 'package:voice_guardian_app/services/api_service.dart';
import 'package:voice_guardian_app/utils/respectfulness_utils.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  late final ApiService _apiService;
  Future<Map<String, dynamic>>? _profileFuture;
  double? _pendingPerspectiveValue;
  bool _isSavingPerspective = false;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureProfileLoaded();
  }

  void _ensureProfileLoaded() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.token == null) {
      setState(() {
        _profileFuture = null;
      });
      return;
    }
    _profileFuture ??= _apiService.getCurrentUser(token: auth.token!);
  }

  Future<void> _refresh() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.token == null) return;
    setState(() {
      _profileFuture = _apiService.getCurrentUser(token: auth.token!);
    });
    await _profileFuture;
  }

  Future<void> _updatePerspectiveThreshold(double value) async {
    setState(() {
      _isSavingPerspective = true;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Provider.of<AuthProvider>(context, listen: false)
          .updatePerspectiveThreshold(value);
      messenger.showSnackBar(
        SnackBar(content: Text('Perspective preference saved (${value.toStringAsFixed(2)})')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to save perspective: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingPerspective = false;
          _pendingPerspectiveValue = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final theme = Theme.of(context);

    if (auth.token == null) {
      return Center(
        child: Text(
          'Log in to see your profile.',
          style: theme.textTheme.titleMedium,
        ),
      );
    }

    final future = _profileFuture;
    if (future == null) {
      return Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 240),
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
                    'Failed to load profile.\nPull to refresh.',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            );
          }
          final data = snapshot.data ?? {};
          final username = data['username']?.toString() ?? auth.username ?? 'Unknown';
          final phone = data['phone_number']?.toString() ?? 'Unknown';
          final respectRaw = data['respectfulness_score'];
          final respectValue = respectRaw is num
              ? respectRaw.toDouble()
              : double.tryParse(respectRaw?.toString() ?? '') ?? 0.0;

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            children: [
              CircleAvatar(
                radius: 48,
                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                child: Text(
                  username.isNotEmpty ? username[0].toUpperCase() : '?',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  username,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  phone,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              Text(
                'Respectfulness Score',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: LinearProgressIndicator(
                              value: respectValue.clamp(0, 100) / 100,
                              minHeight: 8,
                              borderRadius: BorderRadius.circular(8),
                              color: theme.colorScheme.primary,
                          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            respectfulnessGrade(respectValue),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'A higher score means you consistently keep conversations respectful.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Perspective Sensitivity',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Builder(
                        builder: (context) {
                          final sliderValue = (_pendingPerspectiveValue ?? auth.perspectiveThreshold)
                              .clamp(0.05, 0.20)
                              .toDouble();
                          return Slider(
                            min: 0.05,
                            max: 0.20,
                            value: sliderValue,
                            divisions: 15,
                            label: sliderValue.toStringAsFixed(2),
                            onChanged: (value) {
                              setState(() {
                                _pendingPerspectiveValue = value;
                              });
                            },
                            onChangeEnd: (value) {
                              if ((auth.perspectiveThreshold - value).abs() < 0.001) {
                                setState(() {
                                  _pendingPerspectiveValue = null;
                                });
                                return;
                              }
                              _updatePerspectiveThreshold(value);
                            },
                          );
                        },
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text('0.05 • Strict'),
                          Text('0.20 • Moderate'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Lower values prompt coaching earlier; higher values tolerate more nuance.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      if (_isSavingPerspective) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
