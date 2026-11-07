// MCS4302 Week 7 entry point. Run with: flutter run -t lib/main_week7.dart
import 'package:flutter/material.dart';

import 'week7/week7_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Week7App());
}

class Week7App extends StatelessWidget {
  const Week7App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MCS4302 Week 7',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const Week7Page(),
    );
  }
}
