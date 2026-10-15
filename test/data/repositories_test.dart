import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/data/repositories/drift_card_repository.dart';
import 'package:flashcards2/data/repositories/drift_course_repository.dart';
import 'package:flashcards2/data/repositories/drift_review_log_repository.dart';
import 'package:flashcards2/data/repositories/drift_settings_repository.dart';
import 'package:flashcards2/domain/entities/card.dart';
import 'package:flashcards2/domain/entities/course.dart';
import 'package:flashcards2/domain/entities/scheduling.dart';
import 'package:flashcards2/domain/entities/theme.dart';
import 'package:flashcards2/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

/// Behavioral tests for the Drift repository implementations.
///
/// These exercise the interfaces declared in `lib/domain/`, driving them from
/// the domain side only — no Drift types leak into the assertions. That is what
/// keeps the domain layer honestly framework-free rather than nominally so.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late DriftCourseRepository courses;
  late DriftCardRepository cards;
  late DriftReviewLogRepository logs;
  late DriftSettingsRepository settings;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    courses = DriftCourseRepository(db);
    cards = DriftCardRepository(db);
    logs = DriftReviewLogRepository(db);
    settings = DriftSettingsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('CourseRepository', () {
    test('creates, reads back, updates and deletes a course', () async {
      final created = await courses.create(
        Course(
          id: 0,
          name: 'Biology',
          createdAt: DateTime(2026),
          newCardsPerDay: 5,
          interleaveMode: InterleaveMode.blocked,
          archived: false,
        ),
      );
      expect(created.id, isNonZero);

      final found = await courses.findById(created.id);
      expect(found?.name, 'Biology');
      expect(found?.newCardsPerDay, 5);

      await courses.update(
        Course(
          id: created.id,
          name: 'Biology II',
          createdAt: created.createdAt,
          newCardsPerDay: 3,
          interleaveMode: InterleaveMode.interleaved,
          archived: false,
        ),
      );
      final updated = await courses.findById(created.id);
      expect(updated?.name, 'Biology II');
      expect(updated?.interleaveMode, InterleaveMode.interleaved);

      await courses.delete(created.id);
      expect(await courses.findById(created.id), isNull);
    });

    test('hides archived courses unless asked', () async {
      final live = await courses.create(
        Course(
          id: 0,
          name: 'Live',
          createdAt: DateTime(2026),
          newCardsPerDay: 2,
          interleaveMode: InterleaveMode.blocked,
          archived: false,
        ),
      );
      final archived = await courses.create(
        Course(
          id: 0,
          name: 'Archived',
          createdAt: DateTime(2026),
          newCardsPerDay: 2,
          interleaveMode: InterleaveMode.blocked,
          archived: true,
        ),
      );

      final visible = await courses.findAll();
      final all = await courses.findAll(includeArchived: true);

      expect(visible.map((c) => c.id), [live.id]);
      expect(all.map((c) => c.id), containsAll([live.id, archived.id]));
    });
  });

  group('CardRepository', () {
    Future<Course> seedCourse() {
      return courses.create(
        Course(
          id: 0,
          name: 'Physics',
          createdAt: DateTime(2026),
          newCardsPerDay: 2,
          interleaveMode: InterleaveMode.blocked,
          archived: false,
        ),
      );
    }

    test('creates a theme under a course and finds it back', () async {
      final course = await seedCourse();
      final theme = await cards.createTheme(
        Theme(
          id: 0,
          courseId: course.id,
          name: 'Optics',
          createdAt: DateTime(2026),
        ),
      );

      expect(theme.id, isNonZero);
      final themes = await cards.findThemesByCourse(course.id);
      expect(themes.single.name, 'Optics');
    });

    test('creates a card, attaches images and preserves their order', () async {
      final course = await seedCourse();
      final theme = await cards.createTheme(
        Theme(
          id: 0,
          courseId: course.id,
          name: 'Optics',
          createdAt: DateTime(2026),
        ),
      );
      final card = await cards.createCard(
        Card(
          id: 0,
          themeId: theme.id,
          front: 'Front',
          back: 'Back',
          source: CardSource.manual,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );

      await cards.addImage(
        CardImage(id: 0, cardId: card.id, path: '/b.png', position: 1),
      );
      await cards.addImage(
        CardImage(id: 0, cardId: card.id, path: '/a.png', position: 0),
      );

      final images = await cards.findImagesByCard(card.id);
      expect(images.map((i) => i.path), ['/a.png', '/b.png']);
    });

    test('upserts schedule state one-to-one with its card', () async {
      final course = await seedCourse();
      final theme = await cards.createTheme(
        Theme(
          id: 0,
          courseId: course.id,
          name: 'Optics',
          createdAt: DateTime(2026),
        ),
      );
      final card = await cards.createCard(
        Card(
          id: 0,
          themeId: theme.id,
          front: 'q',
          back: 'a',
          source: CardSource.manual,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );

      await cards.upsertScheduleState(
        ScheduleState(
          cardId: card.id,
          stability: 1.5,
          difficulty: 4.5,
          due: DateTime(2026, 2),
          reps: 1,
          lapses: 0,
          state: ReviewState.learning,
        ),
      );
      final first = await cards.findScheduleState(card.id);
      expect(first?.state, ReviewState.learning);
      expect(first?.reps, 1);

      // The second upsert must replace, not duplicate: one row per card.
      await cards.upsertScheduleState(
        ScheduleState(
          cardId: card.id,
          stability: 2.5,
          difficulty: 5,
          due: DateTime(2026, 3),
          reps: 2,
          lapses: 0,
          state: ReviewState.review,
        ),
      );
      final second = await cards.findScheduleState(card.id);
      expect(second?.reps, 2);
      expect(second?.state, ReviewState.review);
    });
  });

  group('ReviewLogRepository', () {
    test('appends logs and returns them newest first', () async {
      final course = await courses.create(
        Course(
          id: 0,
          name: 'History',
          createdAt: DateTime(2026),
          newCardsPerDay: 2,
          interleaveMode: InterleaveMode.blocked,
          archived: false,
        ),
      );
      final theme = await cards.createTheme(
        Theme(
          id: 0,
          courseId: course.id,
          name: 'Modern',
          createdAt: DateTime(2026),
        ),
      );
      final card = await cards.createCard(
        Card(
          id: 0,
          themeId: theme.id,
          front: 'q',
          back: 'a',
          source: CardSource.manual,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );

      await logs.append(
        ReviewLog(
          id: 0,
          cardId: card.id,
          rating: Rating.good,
          reviewedAt: DateTime(2026),
          elapsedDays: 0,
          scheduledDays: 1,
          state: ReviewState.learning,
          durationMs: 1200,
          hintUsed: false,
          barrierCompleted: true,
        ),
      );
      await logs.append(
        ReviewLog(
          id: 0,
          cardId: card.id,
          rating: Rating.easy,
          reviewedAt: DateTime(2026, 1, 3),
          elapsedDays: 2,
          scheduledDays: 4,
          state: ReviewState.review,
          durationMs: 800,
          hintUsed: true,
          barrierCompleted: true,
        ),
      );

      final history = await logs.findByCard(card.id);
      expect(history, hasLength(2));
      expect(history.first.rating, Rating.easy);
      expect(history.first.hintUsed, isTrue);
      expect(history.last.rating, Rating.good);
    });
  });

  group('SettingsRepository', () {
    test('creates the singleton row on first read and updates it', () async {
      final initial = await settings.read();
      expect(initial.id, AppSettings.singletonId);
      expect(initial.themeMode, AppThemeMode.system);

      await settings.update(
        const AppSettings(
          id: AppSettings.singletonId,
          themeMode: AppThemeMode.dark,
          dayCutoffHour: 2,
          apiBaseUrl: 'https://api.example.test',
        ),
      );

      final updated = await settings.read();
      expect(updated.themeMode, AppThemeMode.dark);
      expect(updated.dayCutoffHour, 2);
      expect(updated.apiBaseUrl, 'https://api.example.test');
    });
  });

  group('due cards (T3.3)', () {
    /// Seeds two courses, each with one theme and two cards, all scheduled.
    ///
    /// The second card of course A is due in the future, and course B exists so
    /// the course filter has something to exclude.
    Future<void> seed() async {
      for (final name in <String>['A', 'B']) {
        final course = await courses.create(
          Course(
            id: 0,
            name: name,
            createdAt: DateTime(2022, 12),
            newCardsPerDay: 20,
            interleaveMode: InterleaveMode.blocked,
            archived: false,
          ),
        );
        final theme = await cards.createTheme(
          Theme(
            id: 0,
            courseId: course.id,
            name: '$name-theme',
            createdAt: DateTime(2022, 12),
          ),
        );
        for (var i = 0; i < 2; i++) {
          final card = await cards.createCard(
            Card(
              id: 0,
              themeId: theme.id,
              front: '$name-$i',
              back: 'back',
              source: CardSource.manual,
              createdAt: DateTime(2022, 12),
              updatedAt: DateTime(2022, 12),
            ),
          );
          await cards.upsertScheduleState(
            ScheduleState(
              cardId: card.id,
              stability: 1,
              difficulty: 5,
              // Only the first card of each theme is due.
              due: i == 0 ? DateTime(2022, 12, 2) : DateTime(2023),
              reps: 1,
              lapses: 0,
              state: ReviewState.review,
            ),
          );
        }
      }
    }

    test('returns only cards due at or before the cutoff', () async {
      await seed();
      final due = await cards.findDueEntries(dueBefore: DateTime(2022, 12, 3));
      expect(due, hasLength(2), reason: 'one due card per course');
      expect(due, everyElement(isNotNull));
    });

    test('resolves theme and course through both join hops', () async {
      await seed();
      final due = await cards.findDueEntries(dueBefore: DateTime(2022, 12, 3));
      // If either join hop were wrong these would be null or mismatched.
      for (final entry in due) {
        expect(entry.themeId, greaterThan(0));
        expect(entry.courseId, greaterThan(0));
        expect(entry.cardId, greaterThan(0));
      }
      expect(due.map((e) => e.courseId).toSet(), hasLength(2));
    });

    test('courseId narrows the queue to one course', () async {
      await seed();
      final all = await courses.findAll();
      final onlyA = await cards.findDueEntries(
        dueBefore: DateTime(2022, 12, 3),
        courseId: all.first.id,
      );
      expect(onlyA, hasLength(1));
      expect(onlyA.single.courseId, all.first.id);
    });

    test('an empty queue is returned rather than throwing', () async {
      await seed();
      final due = await cards.findDueEntries(dueBefore: DateTime(2022));
      expect(due, isEmpty);
    });
  });
}
