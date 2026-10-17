import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/data/repositories/drift_card_repository.dart';
import 'package:flashcards2/data/repositories/drift_course_repository.dart';
import 'package:flashcards2/domain/entities/card.dart';
import 'package:flashcards2/domain/entities/course.dart';
import 'package:flashcards2/domain/entities/theme.dart';
import 'package:flashcards2/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scoped candidate fetch for the global card search (T5.7, S5).
///
/// The repository returns every non-archived card with its real theme and
/// course names, in the deterministic order the search screen promises, so
/// the matcher never has to re-join or re-sort.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late DriftCourseRepository courses;
  late DriftCardRepository cards;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    courses = DriftCourseRepository(db);
    cards = DriftCardRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<Course> seedCourse(String name, {bool archived = false}) {
    return courses.create(
      Course(
        id: 0,
        name: name,
        createdAt: DateTime(2026),
        newCardsPerDay: 5,
        interleaveMode: InterleaveMode.blocked,
        archived: archived,
      ),
    );
  }

  Future<Card> seedCard(Course course, String themeName, String front) async {
    final theme = await cards.createTheme(
      Theme(
        id: 0,
        courseId: course.id,
        name: themeName,
        createdAt: DateTime(2026),
      ),
    );
    return await cards.createCard(
      Card(
        id: 0,
        themeId: theme.id,
        front: front,
        back: 'back',
        source: CardSource.manual,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
  }

  group('findCardsWithContext', () {
    test('carries the real theme and course names of every card', () async {
      final course = await seedCourse('Physics');
      await seedCard(course, 'Optics', 'refraction');

      final result = await cards.findCardsWithContext();

      expect(result.single.courseName, 'Physics');
      expect(result.single.theme.name, 'Optics');
      expect(result.single.card.front, 'refraction');
    });

    test('excludes every card of an archived course', () async {
      final live = await seedCourse('Live');
      await seedCard(live, 'T', 'visible');
      final archived = await seedCourse('Archived', archived: true);
      await seedCard(archived, 'T', 'hidden');

      final result = await cards.findCardsWithContext();

      expect(result.map((s) => s.card.front), ['visible']);
    });

    test('a course scope keeps only that course', () async {
      final a = await seedCourse('A');
      await seedCard(a, 'T', 'card-a');
      final b = await seedCourse('B');
      await seedCard(b, 'T', 'card-b');

      final result = await cards.findCardsWithContext(courseId: a.id);

      expect(result.map((s) => s.card.front), ['card-a']);
    });

    test('a theme scope keeps only that theme', () async {
      final course = await seedCourse('A');
      final wanted = await seedCard(course, 'Wanted', 'keep');
      await seedCard(course, 'Dropped', 'drop');

      final theme = (await cards.findThemesByCourse(course.id))
          .firstWhere((t) => t.name == 'Wanted');
      final result = await cards.findCardsWithContext(themeId: theme.id);

      expect(result.map((s) => s.card.id), [wanted.id]);
    });

    test('orders deterministically by course, theme, card id', () async {
      final a = await seedCourse('A');
      await seedCard(a, 'A-2', 'a2-1');
      await seedCard(a, 'A-2', 'a2-2');
      await seedCard(a, 'A-1', 'a1-1');
      final b = await seedCourse('B');
      await seedCard(b, 'B-1', 'b1-1');

      final result = await cards.findCardsWithContext();

      // Theme A-2 was seeded before A-1, so its id leads: the order is
      // deterministic by id within each level, not alphabetical by name.
      expect(
        result.map((s) => s.card.front),
        ['a2-1', 'a2-2', 'a1-1', 'b1-1'],
      );
    });

    test('an empty scope returns an empty list rather than throwing', () async {
      expect(await cards.findCardsWithContext(), isEmpty);
    });
  });
}
