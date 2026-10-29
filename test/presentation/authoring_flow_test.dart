import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flashcards2/presentation/screens/course_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end authoring flow against a real in-memory database.
///
/// Uses the actual Drift stack rather than a fake repository, so the widget
/// layer is exercised against the same queries production uses.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Widget app() {
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: CourseListScreen()),
    );
  }

  testWidgets('empty state explains what to do', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('No courses yet'), findsOneWidget);
    expect(
      find.text('Create a course to start grouping cards by theme.'),
      findsOneWidget,
    );
  });

  testWidgets('creates a course and shows it in the list', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Course'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Biology');
    // The Create button re-enables one frame after the text field updates.
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Biology'), findsOneWidget);
    expect(find.text('No courses yet'), findsNothing);
  });

  testWidgets('a blank name does not create a course', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Course'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('No courses yet'), findsOneWidget);
    expect(await db.select(db.courses).get(), isEmpty);
  });

  testWidgets('a created course is actually persisted', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Course'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'History');
    // The Create button re-enables one frame after the text field updates.
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.courses).get();
    expect(rows, hasLength(1));
    expect(rows.single.name, 'History');
  });

  testWidgets('an existing course renders from the database', (tester) async {
    await db
        .into(db.courses)
        .insert(
          CoursesCompanion.insert(
            name: 'Seeded',
            newCardsPerDay: const Value(10),
            interleaveMode: const Value(InterleaveMode.blocked),
          ),
        );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Seeded'), findsOneWidget);
  });

  testWidgets('tapping a course opens its themes', (tester) async {
    await db
        .into(db.courses)
        .insert(
          CoursesCompanion.insert(
            name: 'Physics',
            newCardsPerDay: const Value(10),
            interleaveMode: const Value(InterleaveMode.blocked),
          ),
        );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Physics'));
    await tester.pumpAndSettle();

    expect(find.text('No themes yet'), findsOneWidget);
  });
}
