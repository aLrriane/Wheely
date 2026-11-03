import 'package:flutter/material.dart';

import 'login_page.dart';
import '../widgets/wheely_logo.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool hidePassword = true;
  bool hideConfirm = true;
  bool _loading = false;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  // the terms, as heading + text pairs. to change the terms, edit this list only.
  // IMPORTANT: every promise in here must match what the app and backend really do.
  // [contact email] must be replaced with a real address before release.
  static const _terms = <(String, String)>[
    (
      'Using Wheely Access',
      'Wheely Access helps you find wheelchair-friendly places on campus and lets you '
          'save places, review them and report accessibility information. Please use '
          'the app responsibly and honestly.',
    ),
    (
      'Information we collect',
      'To create and run your account we collect your username, email address and '
          'password. If you allow it, we use your device location to show nearby '
          'places and routes. We also keep what you submit in the app: reviews, '
          'reports, saved places and photos.',
    ),
    (
      'Your consent',
      'By ticking the box and signing up, you agree to submit this information and to '
          'let Wheely Access collect, store and use it for the purposes in these terms. '
          'You can withdraw your consent at any time by contacting us, but then we may '
          'not be able to keep your account.',
    ),
    (
      'How we use your data',
      'We use your data only to run the app: to sign you in, show places and routes '
          'near you, display reviews and reports, and improve the accessibility '
          'information for everyone. We collect only what the app needs.',
    ),
    (
      'We care about your privacy',
      'Wheely Access takes your privacy seriously. We do not sell your personal data, '
          'and we use reasonable measures to keep it safe. Your password is never '
          'shown to other users.',
    ),
    (
      'What other users can see',
      'Reviews, reports and photos you submit may be visible to other users. Please '
          'do not post anything private, such as other people\'s faces or personal '
          'details.',
    ),
    (
      'Your rights',
      'You may ask to see, correct or delete your personal data, or object to how it '
          'is used, as provided by the Data Privacy Act of 2012 (Republic Act No. '
          '10173) of the Philippines. To do so, contact us at [contact email].',
    ),
    (
      'Accuracy of information',
      'Accessibility information is shared by the community and may be incomplete or '
          'out of date. Please check conditions yourself before you rely on it. The '
          'app is not meant for emergencies.',
    ),
  ];

  Widget _termsBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (title, text) in _terms) ...[
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(text),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  // read-only version of the terms, opened from the link under the Sign Up button
  void _viewTerms() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Terms and Conditions'),
        content: SingleChildScrollView(child: _termsBody()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // pop up page for the Terms and Conditions. the "I agree" checkbox lives in here.
  // gives back true only when the user ticked the box and pressed the agree button
  Future<bool> _showTerms() async {
    var agreed = false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Terms and Conditions'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _termsBody(),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: agreed,
                  onChanged: (v) => setDialog(() => agreed = v ?? false),
                  title: const Text('I agree to the Terms and Conditions'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              // stays disabled until the box is ticked
              onPressed: agreed ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Agree & Sign Up'),
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _signUp() async {
    // quick checks so we don't send the user back to log in with an empty form
    if (_username.text.trim().isEmpty ||
        _email.text.trim().isEmpty ||
        _password.text.isEmpty) {
      _toast('Please fill in all the fields');
      return;
    }
    if (_password.text != _confirm.text) {
      _toast('Passwords do not match');
      return;
    }

    // the terms pop up comes first. no agreement, no account
    final agreed = await _showTerms();
    if (!agreed || !mounted) return;

    // frontend only for now. when the backend is ready, create the account with
    // FirebaseAuth / the users collection here.
    setState(() => _loading = true);
    // pretend we are talking to the server for a moment (no backend yet)
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    setState(() => _loading = false);

    // account "created", so go back to the log in page
    _toast('Account created. Please log in.');
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              // Logo (see lib/widgets/wheely_logo.dart to switch the look)
              const WheelyLogo(),
              const SizedBox(height: 24),
              const Text(
                'Sign Up',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              // Username
              TextField(
                controller: _username,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.person),
                  labelText: 'Username',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              // Email
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.email),
                  labelText: 'Email',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              // Password
              TextField(
                controller: _password,
                obscureText: hidePassword,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock),
                  labelText: 'Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(hidePassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => hidePassword = !hidePassword),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Retype Password
              TextField(
                controller: _confirm,
                obscureText: hideConfirm,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock),
                  labelText: 'Retype Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(hideConfirm ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => hideConfirm = !hideConfirm),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const SizedBox(height: 8),
              // Sign Up button (the terms pop up opens when this is pressed)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.lightBlue.shade100,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: _loading ? null : _signUp,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sign Up', style: TextStyle(fontSize: 18)),
                ),
              ),
              const SizedBox(height: 8),
              // link to read the terms before signing up
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('By signing up you agree to the '),
                  GestureDetector(
                    onTap: _viewTerms,
                    child: Text(
                      'Terms and Conditions',
                      style: TextStyle(
                        decoration: TextDecoration.underline,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Already have an account
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Already have an account?'),
                  TextButton(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                      );
                    },
                    child: const Text('Log In'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
