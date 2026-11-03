import 'package:flutter/material.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _email = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _sendResetLink() {
    // frontend only for now: there is no backend yet, so we just show the
    // confirmation. when the backend is ready, send the reset mail here.
    setState(() => _sent = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 24),
              const Text(
                'Reset Password',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter the email you use to log in and we will send you a link to reset your password.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (!_sent) ...[
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.mail),
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.lightBlue.shade100,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: _sendResetLink,
                    child: const Text('Send reset link', style: TextStyle(fontSize: 18)),
                  ),
                ),
              ] else ...[
                const Icon(Icons.mark_email_read, size: 64, color: Color(0xFF2E9E5B)),
                const SizedBox(height: 16),
                const Text(
                  'Check your email! If an account exists for that address, a password reset link is on its way.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.lightBlue.shade100,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Back to Log In'),
                  ),
                ),
              ],
              if (!_sent) ...[
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back to Log In'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
