// lib/screens/login_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:voice_guardian_app/providers/auth_provider.dart';
import 'package:voice_guardian_app/screens/register_screen.dart'; // Import register screen

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  String _username = '';
  String _password = '';
  String _message = '';
  bool _isGuestProcessing = false;

  Future<void> _login() async {
    if (!mounted) return;
    setState(() { _message = 'Logging in...'; });
    try {
      // Use the provider to log in
      await Provider.of<AuthProvider>(context, listen: false).login(
        _username,
        _password,
      );
      // If successful, the provider state changes and our app
      // will automatically navigate to the home screen.
    } catch (e) {
      if (!mounted) return;
      setState(() { _message = 'Login Failed: $e'; });
    }
  }

  Future<void> _continueAsGuest() async {
    String tempPhone = '';
    final guestPhone = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Guest mode'),
          content: TextField(
            autofocus: true,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone Number',
              prefixText: '+91 ',
            ),
            onChanged: (value) => tempPhone = value.trim(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(tempPhone.trim()),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    final phone = guestPhone?.trim();
    if (phone == null || phone.isEmpty) {
      return;
    }

    if (!mounted) return;
    setState(() {
      _isGuestProcessing = true;
      _message = 'Joining as guest...';
    });
    try {
      await Provider.of<AuthProvider>(context, listen: false).guestLogin(phone);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = 'Guest login failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGuestProcessing = false;
        });
      }
    }
  }

  // ignore: unused_element
  void _goToRegister() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const RegisterScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final fcmWarning = auth.fcmWarning;

    return Scaffold(
      appBar: AppBar(title: const Text('VoiceGuardian Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Username'),
                    onChanged: (value) => _username = value.trim(),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    onChanged: (value) => _password = value,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _login,
              child: const Text('Login'),
            ),
            const SizedBox(height: 12),
            const SizedBox(height: 12),
            TextButton(
              onPressed: null,
              child: const Text(
                'Closed beta – new registrations disabled',
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _isGuestProcessing ? null : _continueAsGuest,
              child: _isGuestProcessing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Continue as guest'),
            ),
            const SizedBox(height: 20),
            if (_message.isNotEmpty)
              Text(
                _message,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            if (fcmWarning != null)
              Container(
                margin: const EdgeInsets.only(top: 12.0),
                padding: const EdgeInsets.all(10.0),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.orange),
                  borderRadius: BorderRadius.circular(8.0),
                  color: Colors.orange.shade50,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fcmWarning,
                      style: const TextStyle(color: Colors.orange),
                    ),
                    TextButton(
                      onPressed: auth.clearFcmWarning,
                      child: const Text('Dismiss'),
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
