import 'dart:io' as dart_io;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

// what the Edit Profile page gives back to the Account page
class ProfileData {
  const ProfileData({required this.name, required this.email, this.photoPath});

  final String name;
  final String email;
  final String? photoPath;
}

// turns a picked photo path into something an avatar can show (null = no photo).
// on the web the picker gives a link instead of a file path
ImageProvider? profileImage(String? path) {
  if (path == null) return null;
  if (kIsWeb) return NetworkImage(path);
  return FileImage(dart_io.File(path));
}

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key, required this.profile});

  final ProfileData profile;

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late final TextEditingController _name = TextEditingController(
    text: widget.profile.name,
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.profile.email,
  );
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  String? _photoPath;
  bool _hideCurrent = true;
  bool _hideNew = true;
  bool _hideConfirm = true;

  @override
  void initState() {
    super.initState();
    _photoPath = widget.profile.photoPath;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        imageQuality: 85,
      );
      if (picked != null && mounted) {
        setState(() => _photoPath = picked.path);
      }
    } catch (_) {
      // permission denied, no camera, etc.
      if (mounted) _toast('Could not open the camera or gallery');
    }
  }

  void _choosePhoto() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.gallery);
              },
            ),
            if (_photoPath != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _photoPath = null);
                },
              ),
          ],
        ),
      ),
    );
  }

  // to connect: save the new name, email and photo to the user's account here, for
  // example FirebaseAuth.instance.currentUser and the users collection
  void _saveProfile() {
    final name = _name.text.trim();
    final email = _email.text.trim();
    if (name.isEmpty) {
      _toast('Please enter a username');
      return;
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _toast('Please enter a valid email');
      return;
    }
    Navigator.pop(
      context,
      ProfileData(name: name, email: email, photoPath: _photoPath),
    );
  }

  // to connect: re-check the current password and set the new one here, for example
  // FirebaseAuth's reauthenticateWithCredential() and then updatePassword()
  void _updatePassword() {
    if (_currentPassword.text.isEmpty) {
      _toast('Please enter your current password');
      return;
    }
    if (_newPassword.text.length < 8) {
      _toast('The new password must be at least 8 characters');
      return;
    }
    if (_newPassword.text == _currentPassword.text) {
      _toast('Please choose a password different from the current one');
      return;
    }
    if (_newPassword.text != _confirmPassword.text) {
      _toast('The new passwords do not match');
      return;
    }
    _currentPassword.clear();
    _newPassword.clear();
    _confirmPassword.clear();
    _toast('Password looks good. It will be saved once the backend is connected.');
  }

  Widget _passwordField(
    TextEditingController controller,
    String label,
    bool hidden,
    VoidCallback onToggle,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        obscureText: hidden,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.lock),
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: Icon(hidden ? Icons.visibility_off : Icons.visibility),
            onPressed: onToggle,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photo = profileImage(_photoPath);

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // profile photo
            Center(
              child: GestureDetector(
                onTap: _choosePhoto,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 55,
                      backgroundColor: Colors.grey.shade400,
                      backgroundImage: photo,
                      child: photo == null
                          ? const Icon(Icons.person, size: 70)
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.lightBlue.shade100,
                        child: const Icon(
                          Icons.photo_camera,
                          size: 18,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            TextButton(
              onPressed: _choosePhoto,
              child: const Text('Change photo'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.person),
                labelText: 'Username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.email),
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.lightBlue.shade100,
                  foregroundColor: Colors.black,
                ),
                onPressed: _saveProfile,
                child: const Text('Save changes', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'Change password',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _passwordField(
              _currentPassword,
              'Current password',
              _hideCurrent,
              () => setState(() => _hideCurrent = !_hideCurrent),
            ),
            _passwordField(
              _newPassword,
              'New password',
              _hideNew,
              () => setState(() => _hideNew = !_hideNew),
            ),
            _passwordField(
              _confirmPassword,
              'Retype new password',
              _hideConfirm,
              () => setState(() => _hideConfirm = !_hideConfirm),
            ),
            SizedBox(
              height: 50,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.black),
                onPressed: _updatePassword,
                child: const Text('Update password'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
