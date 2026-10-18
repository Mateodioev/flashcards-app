import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/data/repositories/drift_card_repository.dart';
import 'package:flashcards2/data/repositories/drift_course_repository.dart';
import 'package:flashcards2/data/repositories/drift_reminder_repository.dart';
import 'package:flashcards2/domain/reminders/reminder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/authoring.dart';

/// Behavioral tests for reminder-subscription persistence (plan §2, S2/S13).
///
/// Driven from the domain side through [DriftReminderRepository]; raw SQL is
/// used only where the *storage* contract itself is under test (the
/// `"0,2,4"` days-of-week encoding and the drift-level UNIQUE constraint).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late DriftCourseRepository courses;
  late DriftCardRepository cards;
  late DriftReminderRepository reminders;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    courses = DriftCourseRepository(db);
    cards = DriftCardRepository(db);
    reminders = DriftReminderRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('round-trip', () {
    test('upserts a global reminder and reads it back', () async {
      final saved = await reminders.upsert(
        const ReminderSubscription(
          scope: ReminderScope.global,
          hour: 18,
          minute: 30,
        ),
      );

      expect(saved.id, isNonZero);
      expect(saved.scope, ReminderScope.global);
      expect(saved.targetId, isNull);
      expect(saved.hour, 18);
      expect(saved.minute, 30);
      expect(saved.daysOfWeek, isNull);
      expect(saved.enabled, isTrue);

      final all = await reminders.findAll();
      expect(all, [saved]);
    });

    test('upserts course and theme reminders with their targets', () async {
      final course = await seedAuthoringCourse(courses, 'Biology');
      final theme = await seedAuthoringTheme(cards, course, 'Cells');

      final courseReminder = await reminders.upsert(
        ReminderSubscription(
          scope: ReminderScope.course,
          targetId: course.id,
          hour: 9,
          minute: 15,
          enabled: false,
        ),
      );
      final themeReminder = await reminders.upsert(
        ReminderSubscription(
          scope: ReminderScope.theme,
          targetId: theme.id,
          hour: 21,
          minute: 45,
        ),
      );

      expect(courseReminder.scope, ReminderScope.course);
      expect(courseReminder.targetId, course.id);
      expect(courseReminder.enabled, isFalse);
      expect(themeReminder.scope, ReminderScope.theme);
      expect(themeReminder.targetId, theme.id);
      expect(
        (await reminders.findAll()).map((s) => s.id),
        containsAll([courseReminder.id, themeReminder.id]),
      );
    });

    test('watchAll emits on change', () async {
      final emissions = reminders.watchAll();
      final expectation = expectLater(
        emissions,
        emitsInOrder([emits(isEmpty), emits(hasLength(1))]),
      );

      await reminders.upsert(
        const ReminderSubscription(
          scope: ReminderScope.global,
          hour: 18,
          minute: 0,
        ),
      );

      await expectation;
    });
  });

  group('daysOfWeek', () {
    test('null round-trips as daily', () async {
      final saved = await reminders.upsert(
        const ReminderSubscription(
          scope: ReminderScope.global,
          hour: 8,
          minute: 0,
        ),
      );
      expect(saved.daysOfWeek, isNull);
      expect(saved.isDaily, isTrue);
    });

    test('serializes sorted day indexes and deserializes them back', () async {
      final saved = await reminders.upsert(
        const ReminderSubscription(
          scope: ReminderScope.global,
          hour: 8,
          minute: 0,
          daysOfWeek: [4, 0, 2],
        ),
      );

      expect(saved.daysOfWeek, [0, 2, 4]);

      // The storage contract is the comma-joined, sorted encoding the domain
      // scheduler documents; a raw read pins it instead of trusting the map.
      final raw = await db
          .customSelect('SELECT days_of_week FROM reminder_subscriptions')
          .getSingle();
      expect(raw.read<String>('days_of_week'), '0,2,4');

      final reread = await reminders.findAll();
      expect(reread.single.daysOfWeek, [0, 2, 4]);
    });
  });

  group('one subscription per (scope, target)', () {
    test('a second upsert on the same target updates in place', () async {
      final course = await seedAuthoringCourse(courses, 'Physics');

      final first = await reminders.upsert(
        ReminderSubscription(
          scope: ReminderScope.course,
          targetId: course.id,
          hour: 8,
          minute: 0,
        ),
      );
      final second = await reminders.upsert(
        ReminderSubscription(
          scope: ReminderScope.course,
          targetId: course.id,
          hour: 19,
          minute: 30,
          daysOfWeek: const [1, 3],
        ),
      );

      expect(second.id, first.id, reason: 'upsert preserves the row id');
      expect(second.hour, 19);
      expect(second.minute, 30);
      expect(second.daysOfWeek, [1, 3]);
      expect(await reminders.findAll(), hasLength(1));
    });

    test('a second global upsert does not duplicate the global row', () async {
      await reminders.upsert(
        const ReminderSubscription(
          scope: ReminderScope.global,
          hour: 7,
          minute: 0,
        ),
      );
      await reminders.upsert(
        const ReminderSubscription(
          scope: ReminderScope.global,
          hour: 20,
          minute: 0,
          enabled: false,
        ),
      );

      final all = await reminders.findAll();
      expect(all, hasLength(1));
      expect(all.single.hour, 20);
      expect(all.single.enabled, isFalse);
    });

    test('different targets keep separate subscriptions', () async {
      final courseA = await seedAuthoringCourse(courses, 'A');
      final courseB = await seedAuthoringCourse(courses, 'B');

      await reminders.upsert(
        ReminderSubscription(
          scope: ReminderScope.course,
          targetId: courseA.id,
          hour: 8,
          minute: 0,
        ),
      );
      await reminders.upsert(
        ReminderSubscription(
          scope: ReminderScope.course,
          targetId: courseB.id,
          hour: 9,
          minute: 0,
        ),
      );

      expect(await reminders.findAll(), hasLength(2));
    });

    test(
      'the UNIQUE constraint rejects a second row for the same course',
      () async {
        final course = await seedAuthoringCourse(courses, 'Chemistry');
        await reminders.upsert(
          ReminderSubscription(
            scope: ReminderScope.course,
            targetId: course.id,
            hour: 8,
            minute: 0,
          ),
        );

        await expectLater(
          db
              .into(db.reminderSubscriptions)
              .insert(
                ReminderSubscriptionsCompanion.insert(
                  scope: ReminderScope.course,
                  courseId: Value(course.id),
                  hour: 9,
                  minute: 0,
                ),
              ),
          throwsA(isA<SqliteException>()),
        );
        expect(await reminders.findAll(), hasLength(1));
      },
    );

    test(
      'the CHECK constraint rejects a course scope without its target',
      () async {
        await expectLater(
          db
              .into(db.reminderSubscriptions)
              .insert(
                ReminderSubscriptionsCompanion.insert(
                  scope: ReminderScope.course,
                  hour: 9,
                  minute: 0,
                ),
              ),
          throwsA(isA<SqliteException>()),
        );
      },
    );
  });

  group('S13 cascade delete', () {
    test('deleting a course removes its reminder', () async {
      final course = await seedAuthoringCourse(courses, 'History');
      await reminders.upsert(
        ReminderSubscription(
          scope: ReminderScope.course,
          targetId: course.id,
          hour: 8,
          minute: 0,
        ),
      );

      await courses.delete(course.id);

      expect(await reminders.findAll(), isEmpty);
    });

    test('deleting a theme removes its reminder', () async {
      final course = await seedAuthoringCourse(courses, 'Geo');
      final theme = await seedAuthoringTheme(cards, course, 'Rivers');
      await reminders.upsert(
        ReminderSubscription(
          scope: ReminderScope.theme,
          targetId: theme.id,
          hour: 8,
          minute: 0,
        ),
      );

      await cards.deleteTheme(theme.id);

      expect(await reminders.findAll(), isEmpty);
    });
  });

  group('delete', () {
    test('removes exactly the targeted subscription', () async {
      final course = await seedAuthoringCourse(courses, 'Music');
      final global = await reminders.upsert(
        const ReminderSubscription(
          scope: ReminderScope.global,
          hour: 8,
          minute: 0,
        ),
      );
      final courseReminder = await reminders.upsert(
        ReminderSubscription(
          scope: ReminderScope.course,
          targetId: course.id,
          hour: 9,
          minute: 0,
        ),
      );

      await reminders.delete(courseReminder.id);

      final remaining = await reminders.findAll();
      expect(remaining, hasLength(1));
      expect(remaining.single.id, global.id);
    });
  });
}
