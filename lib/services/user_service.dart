import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';
import '../models/user.dart';

class UserServiceException implements Exception {
  final String message;

  UserServiceException(this.message);

  @override
  String toString() => message;
}

class UserService {
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static const int minPasswordLength = 8;

  static String? validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Name is required';
    if (name.length > 100) return 'Name must be 100 characters or fewer';
    return null;
  }

  static String? validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Email is required';
    if (!_emailPattern.hasMatch(email)) return 'Enter a valid email address';
    return null;
  }

  static String? validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Password is required';
    if (password.length < minPasswordLength) {
      return 'Password must be at least $minPasswordLength characters';
    }
    if (!password.contains(RegExp(r'[A-Za-z]')) ||
        !password.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain both letters and numbers';
    }
    return null;
  }

  /// Creates an auth account plus its `users` profile without disturbing the
  /// session of the admin performing the action. The account is created on a
  /// short-lived secondary Firebase app so the primary app stays signed in as
  /// the admin, which is also what authorises the profile write.
  static Future<void> createUser({
    required String name,
    required String email,
    required String password,
    required UserRole role,
  }) async {
    final trimmedName = name.trim();
    final trimmedEmail = email.trim();

    final validationError =
        validateName(trimmedName) ??
        validateEmail(trimmedEmail) ??
        validatePassword(password);
    if (validationError != null) {
      throw UserServiceException(validationError);
    }

    final adminUid = FirebaseAuth.instance.currentUser?.uid;
    if (adminUid == null) {
      throw UserServiceException('You must be signed in to create users.');
    }

    final secondaryApp = await Firebase.initializeApp(
      name: 'userProvisioning',
      options: DefaultFirebaseOptions.currentPlatform,
    );

    try {
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      UserCredential credential;
      try {
        credential = await secondaryAuth.createUserWithEmailAndPassword(
          email: trimmedEmail,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        throw UserServiceException(_authErrorMessage(e));
      }

      final createdUser = credential.user;
      if (createdUser == null) {
        throw UserServiceException(
          'Account creation failed. Please try again.',
        );
      }

      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(createdUser.uid)
            .set({
              'email': trimmedEmail,
              'name': trimmedName,
              'role': role.name,
              'createdAt': FieldValue.serverTimestamp(),
              'createdBy': adminUid,
            });
      } catch (e) {
        // Roll back the orphaned auth account so the email can be reused.
        try {
          await createdUser.delete();
        } catch (_) {}
        throw UserServiceException('Could not save the user profile: $e');
      } finally {
        await secondaryAuth.signOut();
      }
    } finally {
      await secondaryApp.delete();
    }
  }

  static Future<void> updateRole(String userId, UserRole role) async {
    final docRef = FirebaseFirestore.instance.collection('users').doc(userId);
    final snapshot = await docRef.get();
    final data = snapshot.data();
    if (data == null) {
      throw UserServiceException('User profile no longer exists.');
    }
    await docRef.set({
      'email': data['email'],
      'name': data['name'],
      'role': role.name,
      if (data['createdAt'] != null) 'createdAt': data['createdAt'],
      if (data['createdBy'] != null) 'createdBy': data['createdBy'],
    });
  }

  /// Removes the profile document, which revokes all app access. The auth
  /// account itself can only be deleted with admin credentials, so it has to
  /// be removed from the Firebase console.
  static Future<void> revokeAccess(String userId) async {
    if (FirebaseAuth.instance.currentUser?.uid == userId) {
      throw UserServiceException('You cannot remove your own access.');
    }
    await FirebaseFirestore.instance.collection('users').doc(userId).delete();
  }

  static String _authErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'That email already has an account.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'weak-password':
        return 'Password is too weak. Use at least $minPasswordLength characters.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is disabled for this Firebase project.';
      default:
        return e.message ?? 'Account creation failed (${e.code}).';
    }
  }
}
