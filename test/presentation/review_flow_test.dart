import 'package:drift/native.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/domain/scheduling/due_queue.dart';
import 'package:flashcards2/domain/scheduling/scheduler.dart';
import 'package:flashcards2/domain/scheduling/session.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flashcards2/presentation/screens/review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end review loop against a real in-memory database.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// Seeds a theme with [count] cards and returns the card ids.
  Future<(int, List<int>)> seedCards(int count) async {
    final courseId = await db
        .into(db.courses)
        .insert(CoursesCompanion.insert(name: 'Course'));
    final themeId = await db
        .into(db.themes)
        .insert(ThemesCompanion.insert(courseId: courseId, name: 'Theme'));
    final ids = <int>[];
    for (var i = 0; i < count; i++) {
      ids.add(
        await db
            .into(db.cards)
            .insert(
              CardsCompanion.insert(
                themeId: themeId,
                front: 'front $i',
                back: 'back $i',
              ),
            ),
      );
    }
    return (themeId, ids);
  }

  Widget app({required List<SessionItem> items, bool barrier = false}) {
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: ReviewScreen(
          items: items,
          scheduler: Scheduler(),
          barrierEnabled: barrier,
        ),
      ),
    );
  }

  testWidgets('shows the front and hides the answer until revealed', (
    tester,
  ) async {
    final (themeId, ids) = await seedCards(1);
    await tester.pumpWidget(
      app(
        items: [
          SessionItem(
            entry: DueEntrySamples.of(ids.first, themeId),
            isNew: true,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('front 0'), findsOneWidget);
    expect(find.text('back 0'), findsNothing);
    expect(find.text('Show answer'), findsOneWidget);
  });

  testWidgets('rating controls appear only after revealing', (tester) async {
    final (themeId, ids) = await seedCards(1);
    await tester.pumpWidget(
      app(
        items: [
          SessionItem(
            entry: DueEntrySamples.of(ids.first, themeId),
            isNew: true,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Good'), findsNothing);
    await tester.tap(find.text('Show answer'));
    await tester.pumpAndSettle();

    expect(find.text('back 0'), findsOneWidget);
    for (final label in ['Again', 'Hard', 'Good', 'Easy']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('closing a session mid-way asks first; staying keeps the card', (
    tester,
  ) async {
    final (themeId, ids) = await seedCards(1);
    await tester.pumpWidget(
      app(
        items: [
          SessionItem(
            entry: DueEntrySamples.of(ids.first, themeId),
            isNew: true,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('End session?'), findsOneWidget);

    await tester.tap(find.text('Keep studying'));
    await tester.pumpAndSettle();
    expect(find.text('front 0'), findsOneWidget);
    expect(find.text('End session?'), findsNothing);
  });

  testWidgets('confirming the exit guard leaves the session', (tester) async {
    final (themeId, ids) = await seedCards(1);
    await tester.pumpWidget(
      app(
        items: [
          SessionItem(
            entry: DueEntrySamples.of(ids.first, themeId),
            isNew: true,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await tester.tap(find.text('End session'));
    await tester.pumpAndSettle();

    expect(find.text('front 0'), findsNothing);
  });

  testWidgets('the barrier disables reveal until an attempt exists', (
    tester,
  ) async {
    final (themeId, ids) = await seedCards(1);
    await tester.pumpWidget(
      app(
        barrier: true,
        items: [
          SessionItem(
            entry: DueEntrySamples.of(ids.first, themeId),
            isNew: true,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // The button is present but inert, and says why.
    expect(find.text('Answer first'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'my attempt');
    await tester.pumpAndSettle();

    expect(find.text('Show answer'), findsOneWidget);
    await tester.tap(find.text('Show answer'));
    await tester.pumpAndSettle();
    expect(find.text('my attempt'), findsOneWidget);
  });

  testWidgets('rating a new card creates its schedule row and a log', (
    tester,
  ) async {
    final (themeId, ids) = await seedCards(1);
    expect(await db.select(db.scheduleStates).get(), isEmpty);

    await tester.pumpWidget(
      app(
        items: [
          SessionItem(
            entry: DueEntrySamples.of(ids.first, themeId),
            isNew: true,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show answer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();

    final states = await db.select(db.scheduleStates).get();
    expect(states, hasLength(1), reason: 'first review creates the row');
    expect(states.single.cardId, ids.first);
    expect(states.single.reps, 1);

    final logs = await db.select(db.reviewLogs).get();
    expect(logs, hasLength(1));
    expect(logs.single.rating, Rating.good);
    expect(logs.single.cardId, ids.first);
  });

  testWidgets('the interval advances according to the scheduler', (
    tester,
  ) async {
    final (themeId, ids) = await seedCards(1);
    await tester.pumpWidget(
      app(
        items: [
          SessionItem(
            entry: DueEntrySamples.of(ids.first, themeId),
            isNew: true,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show answer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Easy'));
    await tester.pumpAndSettle();

    final state = (await db.select(db.scheduleStates).get()).single;
    // Easy on a new card graduates immediately with a day-scale interval.
    expect(state.state, ReviewState.review);
    expect(state.due.isAfter(DateTime.now()), isTrue);
    expect(state.stability, greaterThan(0));
  });

  testWidgets('walks through multiple cards and summarises at the end', (
    tester,
  ) async {
    final (themeId, ids) = await seedCards(2);
    await tester.pumpWidget(
      app(
        items: [
          for (final id in ids)
            SessionItem(entry: DueEntrySamples.of(id, themeId), isNew: true),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 of 2'), findsOneWidget);
    await tester.tap(find.text('Show answer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();

    expect(find.text('2 of 2'), findsOneWidget);
    expect(find.text('front 1'), findsOneWidget);
    expect(find.text('back 1'), findsNothing, reason: 'resets to unrevealed');

    await tester.tap(find.text('Show answer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Again'));
    await tester.pumpAndSettle();

    expect(find.text('Session complete'), findsOneWidget);
    expect(find.text('2 reviewed'), findsOneWidget);
    expect(await db.select(db.reviewLogs).get(), hasLength(2));
  });

  testWidgets('a new card carries a New badge', (tester) async {
    final (themeId, ids) = await seedCards(1);
    await tester.pumpWidget(
      app(
        items: [
          SessionItem(
            entry: DueEntrySamples.of(ids.first, themeId),
            isNew: true,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('New'), findsOneWidget);
  });
}

/// Small helper so the tests read as intent rather than struct plumbing.
abstract final class DueEntrySamples {
  static DueEntry of(int cardId, int themeId) {
    return DueEntry(
      cardId: cardId,
      themeId: themeId,
      courseId: 1,
      due: DateTime(2022, 12),
    );
  }
}
