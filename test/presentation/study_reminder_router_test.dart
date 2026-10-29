import 'package:drift/native.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/domain/entities/course.dart';
import 'package:flashcards2/domain/entities/theme.dart' as domain;
import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/domain/reminders/reminder.dart';
import 'package:flashcards2/domain/reminders/reminder_payload.dart';
import 'package:flashcards2/domain/repositories/card_repository.dart';
import 'package:flashcards2/domain/repositories/course_repository.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flashcards2/presentation/study_reminder_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Member stubs that throw unless a test overrides what it needs — keeps the
/// fakes honest about which lookups a resolution actually performed.
class _Stub {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeCourses extends _Stub implements CourseRepository {
  Map<int, Course> rows = {};

  @override
  Future<Course?> findById(int id) async => rows[id];
}

class _FakeCards extends _Stub implements CardRepository {
  Map<int, domain.Theme> themes = {};

  @override
  Future<domain.Theme?> findThemeById(int id) async => themes[id];
}

final _course = Course(
  id: 5,
  name: 'Biology',
  createdAt: DateTime(2026),
  newCardsPerDay: 5,
  interleaveMode: InterleaveMode.blocked,
  archived: false,
);

final _theme = domain.Theme(
  id: 7,
  courseId: 5,
  name: 'Cells',
  createdAt: DateTime(2026),
);

void main() {
  group('resolveReminderRoute (S11)', () {
    test('global payload needs no lookups', () async {
      final route = await resolveReminderRoute(
        encodeReminderPayload(ReminderScope.global, null),
        courses: _FakeCourses(),
        cards: _FakeCards(),
      );

      expect(route?.scope, ReminderScope.global);
      expect(route?.course, isNull);
      expect(route?.theme, isNull);
    });

    test('course payload resolves the course target', () async {
      final route = await resolveReminderRoute(
        encodeReminderPayload(ReminderScope.course, 5),
        courses: _FakeCourses()..rows[5] = _course,
        cards: _FakeCards(),
      );

      expect(route?.scope, ReminderScope.course);
      expect(route?.course, _course);
      expect(route?.theme, isNull);
    });

    test('theme payload resolves theme and its parent course', () async {
      final route = await resolveReminderRoute(
        encodeReminderPayload(ReminderScope.theme, 7),
        courses: _FakeCourses()..rows[5] = _course,
        cards: _FakeCards()..themes[7] = _theme,
      );

      expect(route?.course, _course);
      expect(route?.theme, _theme);
    });

    test('a target deleted after scheduling routes nowhere (S13 cascade is '
        'the usual guard; this is the last defense)', () async {
      final route = await resolveReminderRoute(
        encodeReminderPayload(ReminderScope.theme, 7),
        courses: _FakeCourses(),
        cards: _FakeCards(),
      );

      expect(route, isNull);
    });

    test('malformed OS payloads route nowhere (untrusted bytes)', () async {
      final route = await resolveReminderRoute(
        'not-json{',
        courses: _FakeCourses(),
        cards: _FakeCards(),
      );

      expect(route, isNull);
    });
  });

  group('routeReminderPayload feedback', () {
    testWidgets('a tap whose target was deleted tells the learner', (
      tester,
    ) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final key = GlobalKey<NavigatorState>();
      WidgetRef? ref;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: Consumer(
            builder: (context, widgetRef, _) {
              ref = widgetRef;
              return MaterialApp(
                navigatorKey: key,
                home: const Scaffold(body: Text('gate resolved')),
              );
            },
          ),
        ),
      );

      await routeReminderPayload(
        encodeReminderPayload(ReminderScope.theme, 7),
        navigatorKey: key,
        ref: ref!,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.textContaining('course or theme no longer exists'),
        findsOneWidget,
        reason: 'a reminder that leads nowhere must say so instead of '
            'silently ignoring the tap',
      );
    });
  });

  group('waitForNavigatorContext', () {
    test('returns null after the attempt budget when no navigator appears',
        () async {
      final key = GlobalKey<NavigatorState>();

      final context = await waitForNavigatorContext(
        key,
        interval: Duration.zero,
        maxAttempts: 2,
      );

      expect(context, isNull);
    });

    testWidgets('waits past the onboarding gate and returns a live context',
        (tester) async {
      final key = GlobalKey<NavigatorState>();
      // The waiter polls on real timers; runAsync gives it a real event
      // loop — await directly and the fake clock never advances.
      final pending = tester.runAsync(() => waitForNavigatorContext(key));

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          home: const Scaffold(body: Text('gate resolved')),
        ),
      );

      expect(await pending, key.currentContext);
    });
  });
}
