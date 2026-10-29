import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flashcards2/presentation/screens/course_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Swipe-to-manage flow for courses and themes, against the real Drift stack:
/// swipe left renames, swipe right deletes behind two confirmations.
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

  Future<int> seedCourse(String name) {
    return db
        .into(db.courses)
        .insert(
          CoursesCompanion.insert(
            name: name,
            newCardsPerDay: const Value(10),
            interleaveMode: const Value(InterleaveMode.blocked),
          ),
        );
  }

  Future<int> seedTheme(int courseId, String name) {
    return db
        .into(db.themes)
        .insert(ThemesCompanion.insert(courseId: courseId, name: name));
  }

  testWidgets('swiping left on a course renames it and persists the change', (
    tester,
  ) async {
    await seedCourse('Biology');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.fling(find.text('Biology'), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    // The rename dialog comes up prefilled with the current name.
    expect(find.text('Rename course'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'Biology');

    await tester.enterText(find.byType(TextField), 'Botany');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Botany'), findsOneWidget);
    expect(find.text('Biology'), findsNothing);
    expect((await db.select(db.courses).get()).single.name, 'Botany');
  });

  testWidgets('renaming keeps the rest of the course settings intact', (
    tester,
  ) async {
    final id = await db
        .into(db.courses)
        .insert(
          CoursesCompanion.insert(
            name: 'Chemistry',
            newCardsPerDay: const Value(7),
            interleaveMode: const Value(InterleaveMode.interleaved),
          ),
        );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.fling(find.text('Chemistry'), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Organic chemistry');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final row = await (db.select(
      db.courses,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(row.name, 'Organic chemistry');
    expect(row.newCardsPerDay, 7);
    expect(row.interleaveMode, InterleaveMode.interleaved);
  });

  testWidgets('cancelling the rename dialog leaves the course unchanged', (
    tester,
  ) async {
    await seedCourse('Biology');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.fling(find.text('Biology'), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Biology'), findsOneWidget);
    expect((await db.select(db.courses).get()).single.name, 'Biology');
  });

  testWidgets(
    'swiping right deletes a course only after both confirmations and '
    'cascades to its themes and cards',
    (tester) async {
      final courseId = await seedCourse('Biology');
      final themeId = await seedTheme(courseId, 'Cells');
      await db
          .into(db.cards)
          .insert(
            CardsCompanion.insert(themeId: themeId, front: 'Q', back: 'A'),
          );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.fling(find.text('Biology'), const Offset(400, 0), 1000);
      await tester.pumpAndSettle();

      // First confirmation explains the cascade impact.
      expect(find.textContaining('Delete course?'), findsOneWidget);
      expect(find.textContaining('1 theme'), findsOneWidget);
      expect(find.textContaining('1 card'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Second confirmation.
      expect(find.text('Really delete?'), findsOneWidget);
      await tester.tap(find.text('Delete permanently'));
      await tester.pumpAndSettle();

      expect(find.text('Biology'), findsNothing);
      expect(await db.select(db.courses).get(), isEmpty);
      expect(await db.select(db.themes).get(), isEmpty);
      expect(await db.select(db.cards).get(), isEmpty);
    },
  );

  testWidgets('bailing on the first delete confirmation keeps the course', (
    tester,
  ) async {
    await seedCourse('Biology');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.fling(find.text('Biology'), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.textContaining('Delete course?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Biology'), findsOneWidget);
    expect(await db.select(db.courses).get(), hasLength(1));
  });

  testWidgets('bailing on the second delete confirmation keeps the course', (
    tester,
  ) async {
    await seedCourse('Biology');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.fling(find.text('Biology'), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Really delete?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Biology'), findsOneWidget);
    expect(await db.select(db.courses).get(), hasLength(1));
  });

  testWidgets('swiping left on a theme renames it and persists the change', (
    tester,
  ) async {
    final courseId = await seedCourse('Biology');
    await seedTheme(courseId, 'Cells');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Biology'));
    await tester.pumpAndSettle();

    await tester.fling(find.text('Cells'), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('Rename theme'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Cell biology');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Cell biology'), findsOneWidget);
    expect((await db.select(db.themes).get()).single.name, 'Cell biology');
  });

  testWidgets('swiping right deletes a theme only after both confirmations', (
    tester,
  ) async {
    final courseId = await seedCourse('Biology');
    final themeId = await seedTheme(courseId, 'Cells');
    await db
        .into(db.cards)
        .insert(CardsCompanion.insert(themeId: themeId, front: 'Q', back: 'A'));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Biology'));
    await tester.pumpAndSettle();

    await tester.fling(find.text('Cells'), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.textContaining('Delete theme?'), findsOneWidget);
    expect(find.textContaining('1 card'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Really delete?'), findsOneWidget);
    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();

    expect(find.text('Cells'), findsNothing);
    expect(await db.select(db.themes).get(), isEmpty);
    expect(await db.select(db.cards).get(), isEmpty);
  });

  group('accessibility hints', () {
    testWidgets('a course row tells screen readers about its swipe actions', (
      tester,
    ) async {
      await seedCourse('Biology');
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      // A MaterialApp carries a dozen Semantics widgets above the row;
      // filter to the ones that declare a hint and expect exactly the row's.
      final hints = tester
          .widgetList<Semantics>(find.widgetWithText(Semantics, 'Biology'))
          .map((s) => s.properties.hint)
          .nonNulls;
      expect(
        hints.where((h) => h.contains('rename')),
        hasLength(1),
        reason: 'a screen reader cannot perform a swipe; the row must say '
            'what the gestures do',
      );
    });

    testWidgets('a theme row tells screen readers about its swipe actions', (
      tester,
    ) async {
      final courseId = await seedCourse('Biology');
      await seedTheme(courseId, 'Cells');
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Biology'));
      await tester.pumpAndSettle();

      final hints = tester
          .widgetList<Semantics>(find.widgetWithText(Semantics, 'Cells'))
          .map((s) => s.properties.hint)
          .nonNulls;
      expect(hints.where((h) => h.contains('rename')), hasLength(1));
    });
  });

  group('create/rename dialog validation', () {
    testWidgets('Create stays disabled until a non-blank name is typed', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Course'));
      await tester.pumpAndSettle();
      expect(find.text('New course'), findsOneWidget);

      var create = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Create'),
      );
      expect(create.onPressed, isNull, reason: 'a blank name must not submit');

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      create = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Create'),
      );
      expect(
        create.onPressed,
        isNull,
        reason: 'whitespace-only is still blank',
      );

      await tester.enterText(find.byType(TextField), 'Biology');
      await tester.pump();
      create = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Create'),
      );
      expect(create.onPressed, isNotNull);
    });

    testWidgets('pressing Enter with a blank name keeps the dialog open', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Course'));
      await tester.pumpAndSettle();

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('New course'), findsOneWidget);
      expect(await db.select(db.courses).get(), isEmpty);
    });
  });

  group('empty state calls to action', () {
    testWidgets('the empty courses list offers to create one', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.text('No courses yet'), findsOneWidget);
      await tester.tap(find.text('Create your first course'));
      await tester.pumpAndSettle();
      expect(find.text('New course'), findsOneWidget);
    });

    testWidgets('the empty themes list offers to create one', (
      tester,
    ) async {
      await seedCourse('Biology');
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Biology'));
      await tester.pumpAndSettle();

      expect(find.text('No themes yet'), findsOneWidget);
      await tester.tap(find.text('Create your first theme'));
      await tester.pumpAndSettle();
      expect(find.text('New theme'), findsOneWidget);
    });
  });

  group('image import feedback', () {
    Widget resultRunner(Object? result) {
      return MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => reportImageImportResult(context, result),
              child: const Text('run'),
            ),
          ),
        ),
      );
    }

    testWidgets('a saved import says how many cards arrived and where', (
      tester,
    ) async {
      await tester.pumpWidget(
        resultRunner((count: 3, theme: 'Cells')),
      );

      await tester.tap(find.text('run'));
      await tester.pump();

      expect(find.text('3 cards added to "Cells".'), findsOneWidget);
    });

    testWidgets('a discarded import says nothing', (tester) async {
      await tester.pumpWidget(resultRunner(null));

      await tester.tap(find.text('run'));
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
