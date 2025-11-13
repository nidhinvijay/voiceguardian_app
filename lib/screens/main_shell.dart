// lib/screens/main_shell.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:voice_guardian_app/providers/auth_provider.dart';
import 'package:voice_guardian_app/screens/friends_screen.dart';
import 'package:voice_guardian_app/screens/history_screen.dart';
import 'package:voice_guardian_app/screens/home_screen.dart';
import 'package:voice_guardian_app/screens/profile_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  late final ValueNotifier<int> _friendsRefreshNotifier = ValueNotifier<int>(0);
  late final List<Widget> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = [
      HomeTab(refreshTrigger: _friendsRefreshNotifier),
      const HistoryTab(),
      FriendsTab(onFriendshipChanged: _signalFriendsRefresh),
      const ProfileTab(),
    ];
  }

  void _signalFriendsRefresh() {
    _friendsRefreshNotifier.value++;
  }

  List<Widget> _buildActions(BuildContext context) {
    if (_currentIndex != 0) {
      return const [];
    }
    return [
      IconButton(
        icon: const Icon(Icons.refresh),
        tooltip: 'Refresh friends',
        onPressed: _signalFriendsRefresh,
      ),
      IconButton(
        icon: const Icon(Icons.logout),
        tooltip: 'Logout',
        onPressed: () => Provider.of<AuthProvider>(context, listen: false).logout(),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Chats', 'History', 'Friends', 'Profile'];
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_currentIndex]),
        actions: _buildActions(context),
        elevation: 0,
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (value) {
          setState(() => _currentIndex = value);
          if (value == 0) {
            _signalFriendsRefresh();
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.group_outlined),
            label: 'Friends',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
        selectedItemColor: theme.colorScheme.primary,
        unselectedItemColor: theme.colorScheme.onSurfaceVariant,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }

  @override
  void dispose() {
    _friendsRefreshNotifier.dispose();
    super.dispose();
  }
}
