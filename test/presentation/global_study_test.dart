import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flashcards2/presentation/screens/course_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Global-level `Study` behaviour against a real in-memory database.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> seedCourse(String name) {
    return db
        .into(db.courses)
        .insert(
          CoursesCompanion.insert(name: name, newCardsPerDay: const Value(10)),
        );
  }

  Future<int> seedTheme(int courseId, String name) {
    return db
        .into(db.themes)
        .insert(ThemesCompanion.insert(courseId: courseId, name: name));
  }

  Future<int> dueCard(int themeId, String front) async {
    final id = await db
        .into(db.cards)
        .insert(
          CardsCompanion.insert(themeId: themeId, front: front, back: 'back'),
        );
    await db
        .into(db.scheduleStates)
        .insert(
          ScheduleStatesCompanion.insert(
            cardId: Value(id),
            due: DateTime(2020),
          ),
        );
    return id;
  }

  Widget app() {
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: CourseListScreen()),
    );
  }

  testWidgets('global Study combines every course, reviews first', (
    tester,
  ) async {
    final courseA = await seedCourse('Course A');
    final courseB = await seedCourse('Course B');
    final themeA = await seedTheme(courseA, 'Theme A');
    final themeB = await seedTheme(courseB, 'Theme B');
    await dueCard(themeA, 'a-due');
    await dueCard(themeB, 'b-due');

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Study'));
    await tester.pumpAndSettle();

    // Ascending course id: course A's block leads, then course B.
    expect(find.text('a-due'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);

    await tester.tap(find.text('Show answer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();

    expect(find.text('b-due'), findsOneWidget);
    expect(find.text('2 of 2'), findsOneWidget);
  });

  testWidgets('an empty account shows the nothing-to-study message', (
    tester,
  ) async {
    await seedCourse('Course A');
    await seedCourse('Course B');

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Study'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing to study here yet.'), findsOneWidget);
  });
}
