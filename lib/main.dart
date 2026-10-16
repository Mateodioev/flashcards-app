import 'package:flashcards2/core/theme.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flashcards2/presentation/screens/course_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(
    ProviderScope(
      overrides: [
        // The only place the on-disk database is constructed. Everything else
        // depends on the provider, which tests swap for an in-memory instance.
        databaseProvider.overrideWithValue(AppDatabase()),
      ],
      child: const FlashcardsApp(),
    ),
  );
}

/// Root of the application.
class FlashcardsApp extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flashcards',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // Persisted override is wired in T7.2; `system` is the default.
      home: const CourseListScreen(),
    );
  }
}
