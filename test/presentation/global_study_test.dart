import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/data/repositories/drift_settings_repository.dart';
import 'package:flashcards2/domain/entities/scheduling.dart';
import 'package:flashcards2/domain/enums.dart';
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

  Future<int> seedCourse(String name, {bool archived = false}) {
    return db
        .into(db.courses)
        .insert(
          CoursesCompanion.insert(
            name: name,
            newCardsPerDay: const Value(10),
            archived: Value(archived),
          ),
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

  Future<int> newCard(int themeId, String front) {
    return db
        .into(db.cards)
        .insert(
          CardsCompanion.insert(themeId: themeId, front: front, back: 'back'),
        );
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

  testWidgets('archived courses are excluded from global Study', (
    tester,
  ) async {
    final live = await seedCourse('Live');
    final archived = await seedCourse('Archived', archived: true);
    final liveTheme = await seedTheme(live, 'Live Theme');
    final archivedTheme = await seedTheme(archived, 'Archived Theme');
    await dueCard(liveTheme, 'live-due');
    await dueCard(archivedTheme, 'archived-due');

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Study'));
    await tester.pumpAndSettle();

    expect(find.text('live-due'), findsOneWidget);
    expect(find.text('archived-due'), findsNothing);
    expect(find.text('1 of 1'), findsOneWidget);
  });

  testWidgets('the global daily ceiling subtracts cards introduced today', (
    tester,
  ) async {
    final settings = DriftSettingsRepository(db);
    final courseA = await seedCourse('Course A');
    final courseB = await seedCourse('Course B');
    final themeA = await seedTheme(courseA, 'Theme A');
    final themeB = await seedTheme(courseB, 'Theme B');

    // memorySpan 3 -> daily ceiling newCardsPerDay(3) == 5.
    await settings.read();
    await settings.update(
      const AppSettings(
        id: AppSettings.singletonId,
        themeMode: AppThemeMode.system,
        dayCutoffHour: 0,
        memorySpan: 3,
      ),
    );

    // Five cards introduced today in course A exhaust the global ceiling.
    for (var i = 0; i < 5; i++) {
      final id = await dueCard(themeA, 'a-due-$i');
      await db
          .into(db.reviewLogs)
          .insert(
            ReviewLogsCompanion.insert(
              cardId: id,
              rating: Rating.good,
              reviewedAt: DateTime.now(),
              state: ReviewState.review,
            ),
          );
    }
    await newCard(themeB, 'b-new');

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Study'));
    await tester.pumpAndSettle();

    // Only the five reviews: the daily ceiling (5 - 5 = 0) admits no new card.
    expect(find.text('1 of 5'), findsOneWidget);
    expect(find.text('b-new'), findsNothing);
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
