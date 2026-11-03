import 'package:flutter/material.dart';

import '../bsu_data.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, required this.place});

  final Place place;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  int _rating = 5;
  final TextEditingController _name = TextEditingController(
    text: 'Anonymous',
  );
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _text.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please write a few words about the place')),
      );
      return;
    }
    widget.place.addReview(
      Review(
        _name.text.trim().isEmpty ? 'Anonymous' : _name.text.trim(),
        _rating.toDouble(),
        text,
        'just now',
      ),
    );
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Write a Review'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                widget.place.name,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              const Text('How accessible was this place?', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      icon: Icon(
                        Icons.star,
                        size: 40,
                        color: i <= _rating ? const Color(0xFFFFB400) : Colors.grey.shade400,
                      ),
                      onPressed: () => setState(() => _rating = i),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _rating == 1
                    ? 'Not accessible at all'
                    : _rating == 2
                    ? 'Hard to access'
                    : _rating == 3
                    ? 'Partly accessible'
                    : _rating == 4
                    ? 'Mostly accessible'
                    : 'Fully accessible',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.person),
                  labelText: 'Your name (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _text,
                maxLines: 5,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.edit),
                  labelText: 'Your review',
                  border: OutlineInputBorder(),
                  hintText: 'How was the ramp, elevator, restroom...?',
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.lightBlue.shade100,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: _submit,
                  child: const Text('Submit review', style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
