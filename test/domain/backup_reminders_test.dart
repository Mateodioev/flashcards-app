import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/data/repositories/drift_card_repository.dart';
import 'package:flashcards2/data/repositories/drift_course_repository.dart';
import 'package:flashcards2/data/repositories/drift_reminder_repository.dart';
import 'package:flashcards2/data/repositories/drift_review_log_repository.dart';
import 'package:flashcards2/data/repositories/drift_settings_repository.dart';
import 'package:flashcards2/domain/backup/backup.dart';
import 'package:flashcards2/domain/backup/backup_io.dart';
import 'package:flashcards2/domain/entities/course.dart';
import 'package:flashcards2/domain/entities/theme.dart' as domain_theme;
import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/domain/reminders/reminder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DriftCourseRepository courses;
  late DriftCardRepository cards;
  late DriftReviewLogRepository logs;
  late DriftSettingsRepository settings;
  late DriftReminderRepository reminders;
  late BackupExporter exporter;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    courses = DriftCourseRepository(db);
    cards = DriftCardRepository(db);
    logs = DriftReviewLogRepository(db);
    settings = DriftSettingsRepository(db);
    reminders = DriftReminderRepository(db);
    exporter = BackupExporter(
      courses: courses,
      cards: cards,
      logs: logs,
      settings: settings,
      reminders: reminders,
    );
  });
  tearDown(() => db.close());

  BackupImporter importerFor(AppDatabase target) {
    return BackupImporter(
      courses: DriftCourseRepository(target),
      cards: DriftCardRepository(target),
      logs: DriftReviewLogRepository(target),
      settings: DriftSettingsRepository(target),
      reminders: DriftReminderRepository(target),
    );
  }

  group('BackupReminder', () {
    test('survives a toJson/fromJson round trip', () {
      const reminder = BackupReminder(
        scope: 'course',
        targetId: 7,
        hour: 18,
        minute: 42,
        daysOfWeek: <int>[1, 3],
        enabled: false,
      );
      final parsed = BackupReminder.fromJson(
        (jsonDecode(jsonEncode(reminder.toJson()))! as Map)
            .cast<String, Object?>(),
      );

      expect(parsed.scope, 'course');
      expect(parsed.targetId, 7);
      expect(parsed.hour, 18);
      expect(parsed.minute, 42);
      expect(parsed.daysOfWeek, <int>[1, 3]);
      expect(parsed.enabled, isFalse);
    });

    test('a global subscription carries no target and no weekday list', () {
      const reminder = BackupReminder(scope: 'global', hour: 9, minute: 5);
      final parsed = BackupReminder.fromJson(
        (jsonDecode(jsonEncode(reminder.toJson()))! as Map)
            .cast<String, Object?>(),
      );

      expect(parsed.targetId, isNull);
      expect(parsed.daysOfWeek, isNull);
      expect(parsed.enabled, isTrue, reason: 'enabled defaults to true');
    });
  });

  group('the reminders key in the format', () {
    test('encode then decode keeps every reminder', () async {
      final course = await courses.create(
        Course(
          id: 0,
          name: 'Biology',
          createdAt: DateTime(2022),
          newCardsPerDay: 10,
          interleaveMode: InterleaveMode.blocked,
          archived: false,
        ),
      );
      await reminders.upsert(
        const ReminderSubscription(
          scope: ReminderScope.global,
          hour: 18,
          minute: 0,
        ),
      );
      await reminders.upsert(
        ReminderSubscription(
          scope: ReminderScope.course,
          targetId: course.id,
          hour: 7,
          minute: 15,
          daysOfWeek: const <int>[0, 2],
          enabled: false,
        ),
      );

      final parsed = Backup.decode((await exporter.export()).encode());

      expect(parsed.reminders, hasLength(2));
      final scoped = parsed.reminders.firstWhere((r) => r.scope == 'course');
      expect(scoped.targetId, course.id);
      expect(scoped.hour, 7);
      expect(scoped.minute, 15);
      expect(scoped.daysOfWeek, <int>[0, 2]);
      expect(scoped.enabled, isFalse);
    });

    test('a v1 export without the key still decodes, as empty', () {
      // Backward compatibility at format version 1: backups written before
      // reminders existed must keep importing.
      final legacy = jsonEncode(<String, Object?>{
        'format': BackupFormat.magic,
        'version': 1,
        'settings': <String, Object?>{
          'themeMode': 'dark',
          'dayCutoffHour': 4,
          'forcedGenerationBarrier': false,
        },
        'courses': <Object?>[],
      });

      expect(Backup.decode(legacy).reminders, isEmpty);
    });
  });

  group('restore (L9): only the global subscription comes back', () {
    test('a course-scoped reminder in the export is skipped, not imported',
        () async {
      await reminders.upsert(
        const ReminderSubscription(
          scope: ReminderScope.global,
          hour: 18,
          minute: 30,
        ),
      );
      final course = await courses.create(
        Course(
          id: 0,
          name: 'Biology',
          createdAt: DateTime(2022),
          newCardsPerDay: 10,
          interleaveMode: InterleaveMode.blocked,
          archived: false,
        ),
      );
      final theme = await cards.createTheme(
        domain_theme.Theme(
          id: 0,
          courseId: course.id,
          name: 'Cells',
          createdAt: DateTime(2022),
        ),
      );
      await reminders.upsert(
        ReminderSubscription(
          scope: ReminderScope.course,
          targetId: course.id,
          hour: 7,
          minute: 0,
        ),
      );
      await reminders.upsert(
        ReminderSubscription(
          scope: ReminderScope.theme,
          targetId: theme.id,
          hour: 8,
          minute: 0,
        ),
      );
      final encoded = (await exporter.export()).encode();

      // Restores get fresh ids for courses/themes, so a target-scoped row
      // would point at a ghost and is skipped by decision (task log L9).
      final fresh = AppDatabase(NativeDatabase.memory());
      addTearDown(fresh.close);
      final freshReminders = DriftReminderRepository(fresh);
      final summary =
          await importerFor(fresh).import(Backup.decode(encoded));

      expect(summary.reminders, 1);
      expect(summary.remindersSkipped, 2);
      final restored = await freshReminders.findAll();
      expect(restored, hasLength(1));
      expect(restored.single.scope, ReminderScope.global);
      expect(restored.single.targetId, isNull);
      expect(restored.single.hour, 18);
      expect(restored.single.minute, 30);
    });

    test('importing twice keeps exactly one global row (upsert, not insert)',
        () async {
      await reminders.upsert(
        const ReminderSubscription(
          scope: ReminderScope.global,
          hour: 18,
          minute: 0,
        ),
      );
      final encoded = (await exporter.export()).encode();

      final fresh = AppDatabase(NativeDatabase.memory());
      addTearDown(fresh.close);
      final freshReminders = DriftReminderRepository(fresh);
      final importer = importerFor(fresh);
      await importer.import(Backup.decode(encoded));
      await importer.import(Backup.decode(encoded));

      // The one-subscription-per-(scope, target) guard lives only in the
      // repository's upsert (log L7); raw inserts would duplicate this row.
      expect(await freshReminders.findAll(), hasLength(1));
    });
  });
}
