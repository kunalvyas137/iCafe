import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'login_screen.dart';
import 'dashboard_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _authError;
  bool _pendingSignOut = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        final user = authSnapshot.data;
        if (user == null) {
          _pendingSignOut = false;
          return LoginScreen(errorMessage: _authError);
        }

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
          builder: (context, roleSnapshot) {
            if (roleSnapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingScreen();
            }

            final doc = roleSnapshot.data;
            if (doc != null && doc.exists) {
              _pendingSignOut = false;
              if (_authError != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _authError = null);
                });
              }
              return const DashboardScreen();
            }

            // No profile document means the account has not been provisioned
            // by an admin. Sign out once and surface the reason on the login
            // screen. A short delay lets a profile written moments ago (e.g.
            // by an admin creating this user) arrive on the stream first.
            if (!_pendingSignOut) {
              _pendingSignOut = true;
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                if (!_pendingSignOut) return;
                await Future.delayed(const Duration(seconds: 1));
                if (!_pendingSignOut) return;
                _pendingSignOut = false;

                if (FirebaseAuth.instance.currentUser == null) return;

                try {
                  await FirebaseAuth.instance.signOut();
                } catch (e) {
                  debugPrint('Sign out failed: $e');
                }
                if (mounted) {
                  setState(() {
                    _authError =
                        'This account has no iCafe profile. Ask an administrator to grant you access.';
                  });
                }
              });
            }

            return const _LoadingScreen();
          },
        );
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
