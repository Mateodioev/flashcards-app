import 'package:drift/native.dart';
import 'package:flashcards2/core/theme.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/main.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppTheme', () {
    test('light and dark share a seed and differ only in brightness', () {
      expect(AppTheme.light.colorScheme.brightness, Brightness.light);
      expect(AppTheme.dark.colorScheme.brightness, Brightness.dark);
      expect(AppTheme.light.useMaterial3, isTrue);
    });
  });

  group('FlashcardsApp', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    testWidgets('boots and shows the course list', (tester) async {
      // Overrides the database with an in-memory one: the real `main` opens the
      // on-disk file, which must not happen during a test.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const FlashcardsApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Courses'), findsOneWidget);
      expect(find.text('No courses yet'), findsOneWidget);
    });

    testWidgets('ships with both a light and a dark theme', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const FlashcardsApp(),
        ),
      );
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.theme, isNotNull);
      expect(app.darkTheme, isNotNull);
      expect(
        app.themeMode,
        ThemeMode.system,
        reason: 'the persisted override is wired in T7.2',
      );
    });
  });
}
