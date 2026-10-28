import 'package:flutter/material.dart';

import 'login_page.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  // Menu button
  Widget menuButton(
      BuildContext context, IconData icon, String text, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.black,
          ),
          icon: Icon(icon),
          label: Align(alignment: Alignment.centerLeft, child: Text(text)),
          onPressed: onTap,
        ),
      ),
    );
  }

  // Snackbar for buttons that don't have a page yet
  void kayLee(BuildContext context) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('bahala ka na Lee')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {},
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            CircleAvatar(
              radius: 55,
              backgroundColor: Colors.grey.shade400,
              child: const Icon(Icons.person, size: 70),
            ),
            const SizedBox(height: 12),
            const Text('Name',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Text('email@gmail.com'),
            const SizedBox(height: 24),
            menuButton(
                context, Icons.edit, 'Edit Profile', () => kayLee(context)),
            menuButton(context, Icons.bookmark_border, 'Saves',
                () => kayLee(context)),
            menuButton(
                context, Icons.history, 'History', () => kayLee(context)),
            menuButton(
                context, Icons.help_outline, 'Help', () => kayLee(context)),
            // Log out - goes back to the Log In page
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.lightBlue.shade100,
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                  );
                },
                child: const Text('Log Out'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
