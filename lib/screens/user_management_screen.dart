import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/user_service.dart';

class UserManagementScreen extends StatelessWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Staff Accounts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateUserDialog(context),
        icon: const Icon(Icons.person_add),
        label: const Text('Add User'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Error loading users.'));
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('No users yet. Tap Add User.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final user = AppUser.fromMap(
                doc.data() as Map<String, dynamic>,
                doc.id,
              );
              final isSelf = doc.id == currentUid;

              return Card(
                child: ListTile(
                  leading: Icon(
                    user.role == UserRole.admin
                        ? Icons.admin_panel_settings
                        : Icons.person,
                  ),
                  title: Text(user.name.isEmpty ? user.email : user.name),
                  subtitle: Text('${user.email} • ${user.role.name}'),
                  trailing: isSelf
                      ? const Chip(label: Text('You'))
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DropdownButton<UserRole>(
                              value: user.role,
                              underline: const SizedBox.shrink(),
                              items: UserRole.values
                                  .map((role) => DropdownMenuItem(
                                        value: role,
                                        child: Text(role.name),
                                      ))
                                  .toList(),
                              onChanged: (role) async {
                                if (role == null || role == user.role) return;
                                await _run(
                                  context,
                                  () => UserService.updateRole(doc.id, role),
                                  'Role updated',
                                );
                              },
                            ),
                            IconButton(
                              tooltip: 'Revoke access',
                              icon: const Icon(Icons.person_remove),
                              onPressed: () =>
                                  _confirmRevoke(context, doc.id, user),
                            ),
                          ],
                        ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmRevoke(
    BuildContext context,
    String userId,
    AppUser user,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke access?'),
        content: Text(
          '${user.email} will immediately lose access to iCafe. '
          'Delete the account in the Firebase console to free up the email address.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await _run(
        context,
        () => UserService.revokeAccess(userId),
        'Access revoked',
      );
    }
  }

  Future<void> _showCreateUserDialog(BuildContext context) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    UserRole role = UserRole.staff;

    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        bool isSaving = false;
        String? error;

        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Add User'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (error != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red[200]!),
                        ),
                        child: Text(
                          error!,
                          style: TextStyle(color: Colors.red[800]),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Full name'),
                      validator: UserService.validateName,
                    ),
                    TextFormField(
                      controller: emailController,
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                      validator: UserService.validateEmail,
                    ),
                    TextFormField(
                      controller: passwordController,
                      decoration: const InputDecoration(
                        labelText: 'Temporary password',
                        helperText:
                            'At least ${UserService.minPasswordLength} characters, letters and numbers',
                      ),
                      obscureText: true,
                      validator: UserService.validatePassword,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<UserRole>(
                      initialValue: role,
                      decoration: const InputDecoration(labelText: 'Role'),
                      items: UserRole.values
                          .map((value) => DropdownMenuItem(
                                value: value,
                                child: Text(value.name),
                              ))
                          .toList(),
                      onChanged: (value) => role = value ?? UserRole.staff,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    isSaving ? null : () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (!(formKey.currentState?.validate() ?? false)) {
                          return;
                        }
                        setState(() {
                          isSaving = true;
                          error = null;
                        });
                        try {
                          await UserService.createUser(
                            name: nameController.text,
                            email: emailController.text,
                            password: passwordController.text,
                            role: role,
                          );
                          if (context.mounted) Navigator.of(context).pop(true);
                        } catch (e) {
                          if (context.mounted) {
                            setState(() {
                              isSaving = false;
                              error = e is UserServiceException
                                  ? e.message
                                  : 'Could not create the user: $e';
                            });
                          }
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create'),
              ),
            ],
          ),
        );
      },
    );

    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();

    if (created == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User created')),
      );
    }
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
    String successMessage,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(e is UserServiceException ? e.message : '$e'),
        ),
      );
    }
  }
}
