import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const GlowStudioApp());
}

class GlowStudioApp extends StatelessWidget {
  const GlowStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFFFF4D8D);
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'Glow Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF0E0E12),
        sliderTheme: const SliderThemeData(
          trackHeight: 3,
          overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
