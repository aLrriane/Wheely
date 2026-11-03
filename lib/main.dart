import 'package:flutter/material.dart';

import 'pages/login_page.dart';

void main() {
  runApp(const WheelyAccessApp());
}

class WheelyAccessApp extends StatelessWidget {
  const WheelyAccessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wheely Access',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.lightBlue,
        useMaterial3: true,
      ),
      home: const LoginPage(),
    );
  }
}
