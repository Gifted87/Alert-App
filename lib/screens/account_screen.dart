import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AccountScreen extends StatelessWidget {
  final User user;
  const AccountScreen({super.key, required this.user});

  Future<void> _deleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your TenX account?'),
        content: const Text(
          'This permanently deletes your Firebase account. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await user.delete();
      if (context.mounted) Navigator.of(context).pop();
    } on FirebaseAuthException catch (error) {
      if (!context.mounted) return;
      final message = error.code == 'requires-recent-login'
          ? 'For security, sign out and sign in again before deleting this account.'
          : (error.message ?? 'Account deletion failed. Please try again.');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = user.displayName?.trim();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('TenX account')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          CircleAvatar(
            radius: 38,
            backgroundColor: const Color(0xFF1C3150),
            backgroundImage: user.photoURL == null
                ? null
                : NetworkImage(user.photoURL!),
            child: user.photoURL != null
                ? null
                : const Icon(
                    Icons.person_rounded,
                    size: 40,
                    color: Color(0xFF64D2FF),
                  ),
          ),
          const SizedBox(height: 14),
          Text(
            name?.isNotEmpty == true ? name! : 'TenX user',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            user.email ?? 'Signed in with Google',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 28),
          Card(
            color: const Color(0xFF171719),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.logout_rounded,
                    color: Color(0xFF64D2FF),
                  ),
                  title: const Text(
                    'Sign out',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () => FirebaseAuth.instance.signOut(),
                ),
                const Divider(height: 1, color: Color(0xFF303034)),
                ListTile(
                  leading: const Icon(
                    Icons.delete_forever_rounded,
                    color: Color(0xFFFF453A),
                  ),
                  title: const Text(
                    'Delete account',
                    style: TextStyle(color: Color(0xFFFF453A)),
                  ),
                  onTap: () => _deleteAccount(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Your alerts, history, strategies, favorites, chart drawings, and app settings sync to your private account. API credentials stay on this device.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, height: 1.4),
          ),
        ],
      ),
    );
  }
}
