// lib/screens/history_screen.dart

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:voice_guardian_app/providers/auth_provider.dart';
import 'package:voice_guardian_app/services/api_service.dart';

class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  final ApiService _apiService = ApiService();
  Future<List<dynamic>>? _historyFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureHistoryLoaded();
  }

  void _ensureHistoryLoaded() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.token == null) {
      setState(() {
        _historyFuture = Future.value(<dynamic>[]);
      });
      return;
    }
    _historyFuture ??= _apiService.getCallHistory(token: auth.token!);
  }

  Future<void> _refresh() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final token = auth.token;
    if (token == null) {
      setState(() {
        _historyFuture = Future.value(<dynamic>[]);
      });
      return;
    }

    final future = _apiService.getCallHistory(token: token);
    setState(() {
      _historyFuture = future;
    });
    await future;
  }

  String _formatTimestamp(String? isoString) {
    if (isoString == null || isoString.isEmpty) {
      return 'Unknown time';
    }
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final months = <String>[
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · $hour:$minute $period';
    } catch (_) {
      return isoString;
    }
  }

  String _formatDuration(dynamic seconds) {
    if (seconds is! num) {
      return '—';
    }
    final total = math.max(0, seconds.round());
    final minutes = total ~/ 60;
    final secs = total % 60;
    if (minutes == 0) {
      return '${secs}s';
    }
    return '${minutes}m ${secs.toString().padLeft(2, '0')}s';
  }

  Color _statusColor(BuildContext context, String status) {
    final normalized = status.toLowerCase();
    if (normalized == 'completed') {
      return Colors.green.shade600;
    }
    if (normalized == 'ringing') {
      return Theme.of(context).colorScheme.primary;
    }
    return Theme.of(context).colorScheme.error;
  }

  @override
  Widget build(BuildContext context) {
    final token = context.select((AuthProvider auth) => auth.token);
    final username = context.select((AuthProvider auth) => auth.username ?? '');
    final theme = Theme.of(context);
    final future = _historyFuture;

    if (token == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Text(
            'Log in to review your recent calls.',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (future == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 120),
              children: const [
                Center(child: CircularProgressIndicator()),
              ],
            );
          }

          if (snapshot.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 120, left: 24, right: 24),
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 64,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Unable to load call history. Pull to refresh.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            );
          }

          final records = snapshot.data ?? <dynamic>[];
          if (records.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 120),
              children: [
                Icon(
                  Icons.history,
                  size: 72,
                  color: theme.colorScheme.primary.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 16),
                Text(
                  'No calls yet.\nKeep the conversation respectful and your history will appear here.',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            );
          }

          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            itemCount: records.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final record = records[index] as Map<String, dynamic>;
              final caller = record['caller_username']?.toString() ?? 'Unknown';
              final callee = record['callee_username']?.toString() ?? 'Unknown';
              final status = record['status']?.toString() ?? 'unknown';
              final startedAt = record['started_at']?.toString();
              final endedAt = record['ended_at']?.toString();
              final durationLabel = _formatDuration(record['duration_seconds']);
              final directionOutgoing = caller == username;
              final counterpart = directionOutgoing ? callee : caller;
              final title = directionOutgoing ? 'Outgoing to $counterpart' : 'Incoming from $counterpart';
              final statusColor = _statusColor(context, status);
              final subtitle = StringBuffer()
                ..write(_formatTimestamp(startedAt))
                ..write(' • ')
                ..write(status[0].toUpperCase() + status.substring(1));
              if (endedAt != null && endedAt.isNotEmpty && status.toLowerCase() == 'completed') {
                subtitle.write(' • $durationLabel');
              } else if (status.toLowerCase() == 'completed') {
                subtitle.write(' • $durationLabel');
              }

              return RepaintBoundary(
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: statusColor.withValues(alpha: 0.12),
                      child: Icon(
                        directionOutgoing ? Icons.north_east : Icons.south_west,
                        color: statusColor,
                      ),
                    ),
                    title: Text(title),
                    subtitle: Text(subtitle.toString()),
                    trailing: Text(
                      status.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
