import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/data/repositories/drift_settings_repository.dart';
import 'package:flashcards2/domain/entities/course.dart';
import 'package:flashcards2/domain/entities/scheduling.dart';
import 'package:flashcards2/domain/entities/theme.dart' as domain;
import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flashcards2/presentation/screens/card_list_screen.dart';
import 'package:flashcards2/presentation/screens/course_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Course-level `Study` behaviour against a real in-memory database.
void main() {
  late AppDatabase db;
  late DriftSettingsRepository settings;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    settings = DriftSettingsRepository(db);
  });

  tearDown(() => db.close());

  Future<Course> seedCourse({
    InterleaveMode mode = InterleaveMode.blocked,
    int newCardsPerDay = 10,
  }) async {
    final id = await db
        .into(db.courses)
        .insert(
          CoursesCompanion.insert(
            name: 'Course',
            newCardsPerDay: Value(newCardsPerDay),
            interleaveMode: Value(mode),
          ),
        );
    return Course(
      id: id,
      name: 'Course',
      createdAt: DateTime(2026),
      newCardsPerDay: newCardsPerDay,
      interleaveMode: mode,
      archived: false,
    );
  }

  Future<(domain.Theme, domain.Theme)> seedThemes(int courseId) async {
    final a = await db
        .into(db.themes)
        .insert(ThemesCompanion.insert(courseId: courseId, name: 'Theme A'));
    final b = await db
        .into(db.themes)
        .insert(ThemesCompanion.insert(courseId: courseId, name: 'Theme B'));
    return (
      domain.Theme(
        id: a,
        courseId: courseId,
        name: 'Theme A',
        createdAt: DateTime(2026),
      ),
      domain.Theme(
        id: b,
        courseId: courseId,
        name: 'Theme B',
        createdAt: DateTime(2026),
      ),
    );
  }

  Future<int> newCard(int themeId, String front) {
    return db
        .into(db.cards)
        .insert(
          CardsCompanion.insert(themeId: themeId, front: front, back: 'back'),
        );
  }

  Future<int> dueCard(int themeId, String front) async {
    final id = await newCard(themeId, front);
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

  Widget themeApp(domain.Theme theme) {
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(home: CardListScreen(theme: theme)),
    );
  }

  Widget app(Course course) {
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(home: ThemeListScreen(course: course)),
    );
  }

  testWidgets('the Study button opens a session spanning all themes', (
    tester,
  ) async {
    final course = await seedCourse(mode: InterleaveMode.interleaved);
    final (themeA, themeB) = await seedThemes(course.id);

    final a1 = await newCard(themeA.id, 'a-front-1');
    final a2 = await newCard(themeA.id, 'a-front-2');
    final b1 = await newCard(themeB.id, 'b-front-1');

    for (final (cardId, due) in <(int, DateTime)>[
      (a1, DateTime(2020)),
      (a2, DateTime(2020, 1, 2)),
      (b1, DateTime(2020)),
    ]) {
      await db
          .into(db.scheduleStates)
          .insert(
            ScheduleStatesCompanion.insert(cardId: Value(cardId), due: due),
          );
    }

    await tester.pumpWidget(app(course));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Study'));
    await tester.pumpAndSettle();

    // Interleaved due order: a1 (theme A), then b1 (theme B), then a2.
    expect(find.text('a-front-1'), findsOneWidget);
    expect(find.text('1 of 3'), findsOneWidget);

    await tester.tap(find.text('Show answer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();

    expect(find.text('b-front-1'), findsOneWidget);
    expect(find.text('2 of 3'), findsOneWidget);
  });

  testWidgets('the daily new-card allowance is applied to the course', (
    tester,
  ) async {
    final course = await seedCourse(newCardsPerDay: 2);
    final (themeA, themeB) = await seedThemes(course.id);

    await newCard(themeA.id, 'a-new-1');
    final b1 = await newCard(themeB.id, 'b-new-1');

    // Pin the cutoff to midnight so "today" is the calendar day and the
    // wall-clock seed below is deterministic regardless of when the test runs.
    final current = await settings.read();
    await settings.update(current.copyWith(dayCutoffHour: 0));

    // b1 was already introduced today, so only a-new-1 remains.
    await db
        .into(db.reviewLogs)
        .insert(
          ReviewLogsCompanion.insert(
            cardId: b1,
            rating: Rating.good,
            reviewedAt: DateTime.now(),
            state: ReviewState.review,
          ),
        );

    await tester.pumpWidget(app(course));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Study'));
    await tester.pumpAndSettle();

    expect(find.text('a-new-1'), findsOneWidget);
    expect(find.text('1 of 1'), findsOneWidget);
  });

  testWidgets('an empty course shows the nothing-to-study message', (
    tester,
  ) async {
    final course = await seedCourse();
    await seedThemes(course.id);

    await tester.pumpWidget(app(course));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Study'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing to study here yet.'), findsOneWidget);
  });

  testWidgets('the forced generation barrier is honoured from settings', (
    tester,
  ) async {
    final course = await seedCourse();
    final (themeA, _) = await seedThemes(course.id);
    await newCard(themeA.id, 'barrier-front');

    // Ensure the singleton row exists before replacing it.
    await settings.read();
    await settings.update(
      const AppSettings(
        id: AppSettings.singletonId,
        themeMode: AppThemeMode.system,
        dayCutoffHour: 4,
        forcedGenerationBarrier: true,
      ),
    );

    await tester.pumpWidget(app(course));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Study'));
    await tester.pumpAndSettle();

    expect(find.text('barrier-front'), findsOneWidget);
    expect(find.text('Answer first'), findsOneWidget);
  });

  testWidgets('theme Study scopes the session to that theme only', (
    tester,
  ) async {
    final course = await seedCourse();
    final (themeA, themeB) = await seedThemes(course.id);

    await dueCard(themeA.id, 'theme-a-due');
    await dueCard(themeB.id, 'theme-b-due');

    await tester.pumpWidget(themeApp(themeA));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Study'));
    await tester.pumpAndSettle();

    expect(find.text('theme-a-due'), findsOneWidget);
    expect(find.text('theme-b-due'), findsNothing);
    expect(find.text('1 of 1'), findsOneWidget);
  });
}
