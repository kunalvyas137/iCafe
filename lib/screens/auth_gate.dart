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

            // No role document; sign out once and show login with an error.
            // Use a flag so that if the document appears before the callback
            // runs (e.g. during registration), we keep the user signed in.
            if (!_pendingSignOut) {
              _pendingSignOut = true;
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                if (!_pendingSignOut) return;
                // Wait briefly to allow a Firestore `set` during registration
                // to appear on the snapshots stream before taking action.
                await Future.delayed(const Duration(seconds: 1));
                if (!_pendingSignOut) return;
                _pendingSignOut = false;

                final currentUser = FirebaseAuth.instance.currentUser;
                if (currentUser == null) return;

                // If no user doc exists yet, check whether this is the very
                // first user. If so, create an admin record so the first
                // account can always recover from a missing-role state.
                try {
                  final usersQuery = await FirebaseFirestore.instance
                      .collection('users')
                      .limit(1)
                      .get();
                  if (usersQuery.docs.isEmpty) {
                    await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).set({
                      'email': currentUser.email,
                      'role': 'admin',
                      'createdAt': FieldValue.serverTimestamp(),
                    });
                    // The snapshots stream will pick up the new doc and
                    // AuthGate will rebuild to the dashboard.
                    return;
                  }
                } catch (e) {
                  debugPrint('Failed to create fallback admin record: $e');
                }

                try {
                  await FirebaseAuth.instance.signOut();
                } catch (e) {
                  debugPrint('Sign out failed: $e');
                }
                if (mounted) {
                  setState(() {
                    _authError = 'User account is not configured in database. Contact Admin.';
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
