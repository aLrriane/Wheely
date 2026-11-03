import 'package:flutter/material.dart';

import '../bsu_data.dart';
import 'edit_profile_page.dart';
import 'help_page.dart';
import 'history_page.dart';
import 'login_page.dart';
import 'saves_page.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  // to connect: read these from the logged in user (FirebaseAuth.instance.currentUser)
  // and the users collection instead of keeping them here
  String _name = 'Name';
  String _email = 'email@gmail.com';
  String? _photoPath;

  // placeholder lists for the Saves and History pages until the backend is ready.
  // to connect: replace with the user's real saved places and visited places
  static final List<Place> _samplePlaces = kPlaces
      .where((p) => p.known)
      .take(3)
      .toList();

  // Menu button
  Widget menuButton(
    BuildContext context,
    IconData icon,
    String text,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: Colors.black),
          icon: Icon(icon),
          label: Align(alignment: Alignment.centerLeft, child: Text(text)),
          onPressed: onTap,
        ),
      ),
    );
  }

  void _open(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _editProfile() async {
    final result = await Navigator.push<ProfileData>(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfilePage(
          profile: ProfileData(
            name: _name,
            email: _email,
            photoPath: _photoPath,
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _name = result.name;
      _email = result.email;
      _photoPath = result.photoPath;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Profile updated')));
  }

  void logOut(BuildContext context) {
    // clears the pages behind, so the back button can't return to the app after log out
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final photo = profileImage(_photoPath);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            CircleAvatar(
              radius: 55,
              backgroundColor: Colors.grey.shade400,
              backgroundImage: photo,
              child: photo == null ? const Icon(Icons.person, size: 70) : null,
            ),
            const SizedBox(height: 12),
            Text(
              _name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(_email),
            const SizedBox(height: 24),
            menuButton(context, Icons.edit, 'Edit Profile', _editProfile),
            menuButton(
              context,
              Icons.bookmark_border,
              'Saves',
              () => _open(SavesPage(places: _samplePlaces)),
            ),
            menuButton(
              context,
              Icons.history,
              'History',
              () => _open(HistoryPage(places: _samplePlaces)),
            ),
            menuButton(
              context,
              Icons.help_outline,
              'Help',
              () => _open(const HelpPage()),
            ),
            // Log out
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.lightBlue.shade100,
                  foregroundColor: Colors.black,
                ),
                onPressed: () => logOut(context),
                child: const Text('Log Out'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
