import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/data/repositories/drift_card_repository.dart';
import 'package:flashcards2/data/repositories/drift_course_repository.dart';
import 'package:flashcards2/data/repositories/drift_reminder_repository.dart';
import 'package:flashcards2/domain/reminders/reminder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/authoring.dart';

/// Regression probes from the independent verifier of the T2 work unit.
/// They pin two invariants the original suite did not: re-upsert CLEARS a
/// previously set weekday list (back to daily) while preserving the row id,
/// and the scope-isolated DAO/repository lookups never let a course query
/// hit a theme row (or vice versa) when ids collide across tables.
void main() {
  late AppDatabase db;
  late DriftReminderRepository repository;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repository = DriftReminderRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('re-upsert without weekdays clears the row back to daily, same id',
      () async {
    final first = await repository.upsert(
      const ReminderSubscription(
        scope: ReminderScope.global,
        hour: 18,
        minute: 30,
        daysOfWeek: [3, 1],
      ),
    );
    expect(first.daysOfWeek, [1, 3], reason: 'stored sorted');

    final second = await repository.upsert(
      const ReminderSubscription(
        scope: ReminderScope.global,
        hour: 7,
        minute: 45,
      ),
    );

    expect(second.id, first.id);
    expect(second.hour, 7);
    expect(second.isDaily, isTrue,
        reason: 'a later daily upsert replaces weekly, it never merges');
    expect(await repository.findAll(), hasLength(1),
        reason: 'upsert never grows the table');
  });

  test('course and theme lookups stay scope-isolated when ids collide',
      () async {
    // Courses and themes auto-increment independently, so in a small
    // database course 1 and theme 1 coexist — a targetId-keyed lookup that
    // ignored scope could resolve the wrong subscription.
    final courses = DriftCourseRepository(db);
    final cards = DriftCardRepository(db);
    final course = await seedAuthoringCourse(courses, 'Verifer Course');
    final theme = await seedAuthoringTheme(cards, course, 'Verifier Theme');
    expect(theme.id, course.id, reason: 'probe premise: colliding ids');

    await repository.upsert(
      ReminderSubscription(
        scope: ReminderScope.theme,
        targetId: theme.id,
        hour: 9,
        minute: 0,
      ),
    );

    final list = await repository.findAll();
    expect(list, hasLength(1));
    final row = list.single;
    expect(row.scope, ReminderScope.theme);
    expect(row.targetId, theme.id);

    // A course-scoped upsert with the same numeric id must create a NEW row,
    // not match the theme row.
    await repository.upsert(
      ReminderSubscription(
        scope: ReminderScope.course,
        targetId: course.id,
        hour: 10,
        minute: 0,
      ),
    );
    expect(await repository.findAll(), hasLength(2),
        reason: 'same numeric id in a different scope is a different target');
  });
}
