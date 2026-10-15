import 'package:flashcards2/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(const ProviderScope(child: FlashcardsApp()));
}

/// Root of the application.
///
/// Theming is Material 3 with light/dark/system selection; the persisted
/// override is wired in a later task (T7.2). This shell exists so the project
/// has a real entry point instead of the `flutter create` counter demo.
class FlashcardsApp extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flashcards',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const _HomePlaceholder(),
    );
  }
}

class _HomePlaceholder extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flashcards')),
      body: const Center(child: Text('No courses yet.')),
    );
  }
}
