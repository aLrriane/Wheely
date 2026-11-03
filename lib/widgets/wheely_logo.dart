import 'package:flutter/material.dart';

// the Wheely Access logo, used on the log in page, the sign up page and the menu header
class WheelyLogo extends StatelessWidget {
  const WheelyLogo({super.key, this.compact = false});

  // true in the menu header, where the app name is already written next to the logo.
  // false on the log in and sign up pages: logo with the app name and tagline under it
  final bool compact;

  static const _asset = 'assets/images/wheely_logo.png';
  static const _label = 'Wheely Access logo';

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Image.asset(_asset, height: 56, semanticLabel: _label);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(_asset, height: 120, semanticLabel: _label),
        const SizedBox(height: 14),
        const Text(
          'Wheely Access',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Find PWD-friendly places',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}
