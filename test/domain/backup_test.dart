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
import 'package:flashcards2/domain/entities/card.dart' as domain;
import 'package:flashcards2/domain/entities/course.dart';
import 'package:flashcards2/domain/entities/scheduling.dart';
import 'package:flashcards2/domain/entities/theme.dart' as domain;
import 'package:flashcards2/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DriftCourseRepository courses;
  late DriftCardRepository cards;
  late DriftReviewLogRepository logs;
  late DriftSettingsRepository settings;
  late BackupExporter exporter;
  late BackupImporter importer;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    courses = DriftCourseRepository(db);
    cards = DriftCardRepository(db);
    logs = DriftReviewLogRepository(db);
    settings = DriftSettingsRepository(db);
    exporter = BackupExporter(
      courses: courses,
      cards: cards,
      logs: logs,
      settings: settings,
      reminders: DriftReminderRepository(db),
    );
    importer = BackupImporter(
      courses: courses,
      cards: cards,
      logs: logs,
      settings: settings,
      reminders: DriftReminderRepository(db),
    );
  });
  tearDown(() => db.close());

  /// Seeds one course, one theme, one reviewed card.
  Future<void> seed() async {
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
      domain.Theme(
        id: 0,
        courseId: course.id,
        name: 'Cells',
        createdAt: DateTime(2022),
      ),
    );
    final card = await cards.createCard(
      domain.Card(
        id: 0,
        themeId: theme.id,
        front: r'What is $\frac{1}{2}$?',
        back: 'One half',
        source: CardSource.manual,
        createdAt: DateTime(2022),
        updatedAt: DateTime(2022),
      ),
    );
    await cards.upsertScheduleState(
      ScheduleState(
        cardId: card.id,
        stability: 3.5,
        difficulty: 5.25,
        due: DateTime(2022, 3),
        lastReview: DateTime(2022, 2),
        reps: 4,
        lapses: 1,
        state: ReviewState.review,
      ),
    );
    await logs.append(
      ReviewLog(
        id: 0,
        cardId: card.id,
        rating: Rating.good,
        reviewedAt: DateTime(2022, 2),
        elapsedDays: 1.5,
        scheduledDays: 2.75,
        state: ReviewState.review,
        durationMs: 5200,
        hintUsed: true,
        barrierCompleted: true,
      ),
    );
  }

  group('round trip', () {
    test('content survives export and import', () async {
      await seed();
      final backup = await exporter.export();
      final encoded = backup.encode();

      // Into a fresh database, as a restore onto a new device would.
      final fresh = AppDatabase(NativeDatabase.memory());
      addTearDown(fresh.close);
      final imported = await BackupImporter(
        courses: DriftCourseRepository(fresh),
        cards: DriftCardRepository(fresh),
        logs: DriftReviewLogRepository(fresh),
        settings: DriftSettingsRepository(fresh),
        reminders: DriftReminderRepository(fresh),
      ).import(Backup.decode(encoded));

      expect(imported.courses, 1);
      expect(imported.themes, 1);
      expect(imported.cards, 1);
      expect(imported.logs, 1);

      final restoredCourses = await DriftCourseRepository(fresh).findAll();
      expect(restoredCourses.single.name, 'Biology');

      final restoredThemes = await DriftCardRepository(fresh)
          .findThemesByCourse(restoredCourses.single.id);
      final restoredCards = await DriftCardRepository(fresh)
          .findCardsByTheme(restoredThemes.single.id);

      expect(
        restoredCards.single.front,
        r'What is $\frac{1}{2}$?',
        reason: 'LaTeX must survive the round trip byte for byte',
      );
    });

    test('scheduling state survives, so history is not reset', () async {
      await seed();
      final encoded = (await exporter.export()).encode();

      final fresh = AppDatabase(NativeDatabase.memory());
      addTearDown(fresh.close);
      final freshCards = DriftCardRepository(fresh);
      await BackupImporter(
        courses: DriftCourseRepository(fresh),
        cards: freshCards,
        logs: DriftReviewLogRepository(fresh),
        settings: DriftSettingsRepository(fresh),
        reminders: DriftReminderRepository(fresh),
      ).import(Backup.decode(encoded));

      final course = (await DriftCourseRepository(fresh).findAll()).single;
      final theme = (await freshCards.findThemesByCourse(course.id)).single;
      final card = (await freshCards.findCardsByTheme(theme.id)).single;
      final state = await freshCards.findScheduleState(card.id);

      expect(state, isNotNull);
      expect(state!.reps, 4);
      expect(state.lapses, 1);
      expect(state.stability, 3.5);
      expect(
        state.difficulty,
        5.25,
        reason: 'difficulty is fractional; an int format would truncate it',
      );
      expect(state.state, ReviewState.review);
    });

    test('fractional day counts survive, not truncated', () async {
      await seed();
      final encoded = (await exporter.export()).encode();
      final parsed = Backup.decode(encoded);
      final log = parsed.courses.single.themes.single.cards.single.logs.single;

      // Guards a real bug in an earlier draft: the format used int for these,
      // which silently dropped the fraction on export.
      expect(log.elapsedDays, 1.5);
      expect(log.scheduledDays, 2.75);
    });
  });

  group('the API key never leaves the device', () {
    test('is absent from the exported file', () async {
      await seed();
      final encoded = (await exporter.export()).encode();

      expect(
        encoded.toLowerCase(),
        isNot(contains('apikey')),
        reason: 'the field must not exist at all, not merely be empty',
      );
      expect(encoded, isNot(contains('apiBaseUrl')));
      expect(encoded, isNot(contains('apiModelId')));
      // A backup gets copied around: cloud drives, email, chat. A credential in
      // one is a credential published.
      expect(encoded, isNot(contains('Bearer')));
    });

    test('an export carries only the safe settings', () async {
      await seed();
      final backup = await exporter.export();
      final json = jsonDecode(backup.encode()) as Map<String, Object?>;
      final settingsJson = json['settings']! as Map<String, Object?>;

      expect(
        settingsJson.keys,
        unorderedEquals(<String>[
          'themeMode',
          'dayCutoffHour',
          'forcedGenerationBarrier',
          'memorySpan',
          'onboardingCompletedAt',
        ]),
        reason: 'an allowlist means a future credential column stays out',
      );
    });
  });

  group('the file is validated before anything is written', () {
    test('rejects a non-JSON file', () {
      expect(
        () => Backup.decode('this is not json'),
        throwsA(
          isA<BackupFormatException>().having(
            (e) => e.message,
            'message',
            contains('not valid JSON'),
          ),
        ),
      );
    });

    test('rejects JSON that is not a backup', () {
      expect(
        () => Backup.decode('{"hello":"world"}'),
        throwsA(
          isA<BackupFormatException>().having(
            (e) => e.message,
            'message',
            contains('not created by this app'),
          ),
        ),
      );
    });

    test('rejects a backup from a newer app version', () {
      final future = jsonEncode(<String, Object?>{
        'format': BackupFormat.magic,
        'version': BackupFormat.version + 1,
        'settings': <String, Object?>{},
        'courses': <Object?>[],
      });
      expect(
        () => Backup.decode(future),
        throwsA(
          isA<BackupFormatException>().having(
            (e) => e.message,
            'message',
            contains('newer version'),
          ),
        ),
      );
    });

    test('rejects a truncated backup', () {
      // Truncation is the realistic corruption: a copy interrupted mid-write.
      const truncated =
          '{"format":"${BackupFormat.magic}","version":1,"courses":[{"id":1,';
      expect(
        () => Backup.decode(truncated),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('a damaged file leaves existing data completely untouched', () async {
      // The property that matters most. A failed import must not be able to
      // cost the learner what they already had.
      await seed();

      const damaged =
          '{"format":"${BackupFormat.magic}","version":1,'
          '"courses":[{"id":1,"name":"X"}],"settings":{}}';

      // Decoding is what rejects it, because the course is missing required
      // fields. It must reject BEFORE the importer is reached, so nothing is
      // written and the existing rows are untouched.
      await expectLater(
        Future<void>.sync(() => importer.import(Backup.decode(damaged))),
        throwsA(isA<BackupFormatException>()),
      );

      final stillThere = await courses.findAll();
      expect(stillThere, hasLength(1));
      expect(stillThere.single.name, 'Biology');
      expect(
        await cards.findCardsByTheme(
          (await cards.findThemesByCourse(stillThere.single.id)).single.id,
        ),
        hasLength(1),
      );
    });

    test(
      'surfaces a damaged field as a readable message, not a cast error',
      () {
        // A raw `type 'Null' is not a subtype of type 'int'` tells a learner
        // nothing. The message has to be actionable.
        final broken = jsonEncode(<String, Object?>{
          'format': BackupFormat.magic,
          'version': 1,
          'settings': <String, Object?>{},
          'courses': <Object?>[
            <String, Object?>{'id': 'not a number'},
          ],
        });

        expect(
          () => Backup.decode(broken),
          throwsA(
            isA<BackupFormatException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('incomplete or damaged'),
                isNot(contains('subtype')),
              ),
            ),
          ),
        );
      },
    );
  });

  group('restoring into populated data', () {
    test('adds rather than replacing', () async {
      await seed();
      final encoded = (await exporter.export()).encode();

      // Import back into the SAME database. Ids must not collide or overwrite.
      final summary = await importer.import(Backup.decode(encoded));

      expect(summary.courses, 1);
      final all = await courses.findAll();
      expect(
        all,
        hasLength(2),
        reason: 'a restore is additive; the original must survive',
      );
    });

    test('imported cards are independent of the originals', () async {
      await seed();
      final encoded = (await exporter.export()).encode();
      await importer.import(Backup.decode(encoded));

      final all = await courses.findAll();
      final cardCounts = <int>[];
      for (final course in all) {
        final themes = await cards.findThemesByCourse(course.id);
        for (final theme in themes) {
          cardCounts.add((await cards.findCardsByTheme(theme.id)).length);
        }
      }
      expect(cardCounts, everyElement(1));
    });

    test(
      'restoring a backup with no span does not clear a measured one',
      () async {
        // A backup from before onboarding must not wipe a span measured on this
        // device. That is the one destructive thing a restore could do.
        await seed();
        final current = await settings.read();
        await settings.update(current.copyWith(memorySpan: 7));

        final noSpan = Backup(
          exportedAt: DateTime(2022),
          courses: const <BackupCourse>[],
          settings: const BackupSettings(
            themeMode: 'dark',
            dayCutoffHour: 4,
            forcedGenerationBarrier: false,
          ),
        );
        await importer.import(noSpan);

        final after = await settings.read();
        expect(after.memorySpan, 7, reason: 'the measured span must survive');
        expect(after.themeMode, AppThemeMode.dark);
      },
    );
  });
}
