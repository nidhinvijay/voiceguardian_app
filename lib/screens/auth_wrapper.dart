// lib/screens/auth_wrapper.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:voice_guardian_app/providers/auth_provider.dart';
import 'package:voice_guardian_app/screens/main_shell.dart';
import 'package:voice_guardian_app/screens/login_screen.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // Watch the AuthProvider for changes
    final authProvider = Provider.of<AuthProvider>(context);

    if (authProvider.isLoggedIn) {
      return const MainShell();
    } else {
      return const LoginScreen();
    }
  }
}