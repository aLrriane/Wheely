import 'package:flutter/material.dart';

import '../bsu_data.dart';

// TODO: replace with the real support email before release
const String kSupportEmail = '[support email]';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  static const _faqs = <(String, String)>[
    (
      'How do I find the nearest accessible restroom?',
      'Tap the filter button next to the search bar, then choose "Find nearest '
          'accessible restroom". It measures a straight line from your location, or '
          'from the middle of the map if your location is off.',
    ),
    (
      'How do I get directions?',
      'Tap the directions button on the map, then choose where you are starting '
          'from and where you want to go.',
    ),
    (
      'How do I save a place?',
      'Open a place and tap Save. Your saved places show up under Saves in the '
          'menu and on the saved places button on the map.',
    ),
    (
      'How do I report a problem, like a broken elevator?',
      'Open the place and tap Report a problem, pick what is wrong and add a note '
          'if you like.',
    ),
    (
      'Why does a place show no information?',
      'Grey means nobody has reported on it yet. Once you open a place you can add '
          'a photo, write a review or report a problem to help other people.',
    ),
    (
      'Why can\'t the app find my location?',
      'Turn on your phone\'s GPS and allow location access for Wheely Access. '
          'Then tap the My location button on the map.',
    ),
    (
      'How accurate is the information?',
      'Accessibility information is shared by the community and may be incomplete '
          'or out of date. Please check conditions yourself before you rely on it.',
    ),
  ];

  Widget _heading(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _dotLine(Color color, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget _lineLine(Color color, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 4,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  // to connect: send the message to the backend (or an email service) here
  Future<void> _sendFeedback(BuildContext context) async {
    final message = await showDialog<String>(
      context: context,
      builder: (_) => const _FeedbackDialog(),
    );
    if (message == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Thanks! Your message will be sent once the backend is connected.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          // 1. reading the map
          _heading(context, 'Reading the map'),
          const Text(
            'Pin and building colors',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          _dotLine(kAccessible, 'Green: has a ramp, an elevator and an accessible restroom'),
          _dotLine(kPartial, 'Orange: has some accessibility features'),
          _dotLine(kInaccessible, 'Red: has none of these features'),
          _dotLine(Colors.grey, 'Grey: nobody has reported on this place yet'),
          const SizedBox(height: 12),
          const Text(
            'Walkway lines',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          _lineLine(kAccessible, 'Smooth and flat'),
          _lineLine(kPartial, 'Slope or narrow, be careful'),
          _lineLine(kInaccessible, 'Has steps'),
          const SizedBox(height: 12),
          const Text(
            'Filters',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap the filter button next to the search bar to show only certain '
            'places, like colleges, or places with a ramp or an elevator. Press and '
            'hold the button to clear all filters.',
          ),

          // 2. questions people ask
          _heading(context, 'Frequently asked questions'),
          for (final (question, answer) in _faqs)
            ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              title: Text(question),
              children: [Text(answer)],
            ),

          // 3. contact
          _heading(context, 'Contact us'),
          const Text(
            'Something not working, or an idea to make Wheely Access better? '
            'Send us a message.',
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.lightBlue.shade100,
                foregroundColor: Colors.black,
              ),
              icon: const Icon(Icons.feedback_outlined),
              label: const Text('Report a problem or send feedback'),
              onPressed: () => _sendFeedback(context),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Or email us at blank'),
        ],
      ),
    );
  }
}

// the "send feedback" pop up. it owns its text box so the box is cleaned up properly
class _FeedbackDialog extends StatefulWidget {
  const _FeedbackDialog();

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Please write a short message');
      return;
    }
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Send feedback'),
      content: TextField(
        controller: _controller,
        maxLines: 5,
        minLines: 3,
        decoration: InputDecoration(
          hintText: 'Tell us what went wrong or what we can improve',
          border: const OutlineInputBorder(),
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _send, child: const Text('Send')),
      ],
    );
  }
}
