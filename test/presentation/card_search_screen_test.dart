import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/data/repositories/drift_card_repository.dart';
import 'package:flashcards2/data/repositories/drift_course_repository.dart';
import 'package:flashcards2/domain/entities/card.dart' as domain;
import 'package:flashcards2/domain/entities/course.dart';
import 'package:flashcards2/domain/entities/theme.dart' as domain;
import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flashcards2/presentation/screens/card_editor_screen.dart';
import 'package:flashcards2/presentation/screens/card_search_screen.dart';
import 'package:flashcards2/presentation/screens/course_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Global card search, end to end against a real in-memory database (T5.7).
///
/// The widget layer is exercised against the same Drift queries production
/// uses; data is seeded through the repositories rather than the UI.
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

  Widget app() {
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: CourseListScreen()),
    );
  }

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

  Future<domain.Theme> seedTheme(Course course, String name) {
    return cards.createTheme(
      domain.Theme(
        id: 0,
        courseId: course.id,
        name: name,
        createdAt: DateTime(2026),
      ),
    );
  }

  Future<domain.Card> seedCard(
    domain.Theme theme,
    String front,
    String back,
  ) {
    return cards.createCard(
      domain.Card(
        id: 0,
        themeId: theme.id,
        front: front,
        back: back,
        source: CardSource.manual,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
  }

  Future<void> openSearch(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Search cards'));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).first, text);
    await tester.pumpAndSettle();
  }

  testWidgets('the course list exposes a search entry that opens the screen',
      (tester) async {
    await seedCourse('Physics');

    await openSearch(tester);

    expect(find.byType(CardSearchScreen), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets(
    'typing shows the matching card with its course and theme context',
    (tester) async {
      final course = await seedCourse('Physics');
      final theme = await seedTheme(course, 'Optics');
      await seedCard(theme, 'Why the moon shines', 'reflection');
      await seedCard(theme, 'Speed of light', 'constant');

      await openSearch(tester);
      await type(tester, 'moon');

      expect(find.text('Why the moon shines'), findsOneWidget);
      expect(find.text('Physics › Optics'), findsOneWidget);
      expect(find.text('Speed of light'), findsNothing);
    },
  );

  testWidgets('a phrase spanning a math span matches, and LaTeX renders',
      (tester) async {
      final course = await seedCourse('Math');
      final theme = await seedTheme(course, 'Algebra');
      await seedCard(theme, r'sum of $x^2$ total', 'qed');

      await openSearch(tester);
      await type(tester, 'sum of x^2 total');

      // The delimiters-insensitive match landed: the result row renders the
      // literal segments as text (not raw dollar signs to read).
      expect(find.text('sum of '), findsOneWidget);
      expect(find.text(' total'), findsOneWidget);
      expect(find.textContaining(r'$x^2$'), findsNothing);
    });

  testWidgets('a blank query shows the idle hint and no card rows',
      (tester) async {
    final course = await seedCourse('Physics');
    final theme = await seedTheme(course, 'Optics');
    await seedCard(theme, 'any card', 'x');

    await openSearch(tester);
    await type(tester, '   ');

    expect(
      find.text('Type to find cards across every course by text or LaTeX.'),
      findsOneWidget,
    );
    expect(find.text('any card'), findsNothing);
  });

  testWidgets('a query with no match explains it instead of going silent',
      (tester) async {
    final course = await seedCourse('Physics');
    final theme = await seedTheme(course, 'Optics');
    await seedCard(theme, 'any card', 'x');

    await openSearch(tester);
    await type(tester, 'mars');

    expect(find.textContaining('No results for "mars"'), findsOneWidget);
  });

  testWidgets('course and theme chips narrow the results', (tester) async {
    final physics = await seedCourse('Physics');
    final optics = await seedTheme(physics, 'Optics');
    final wave = await seedTheme(physics, 'Waves');
    await seedCard(optics, 'light bends', 'refraction');
    await seedCard(wave, 'light travels', 'wavefront');

    await openSearch(tester);
    await type(tester, 'light');
    expect(find.text('light bends'), findsOneWidget);
    expect(find.text('light travels'), findsOneWidget);

    await tester.tap(find.text('Physics'));
    await tester.pumpAndSettle();
    expect(find.text('light bends'), findsOneWidget);
    expect(find.text('light travels'), findsOneWidget);

    await tester.tap(find.text('Optics'));
    await tester.pumpAndSettle();
    expect(find.text('light bends'), findsOneWidget);
    expect(find.text('light travels'), findsNothing);
  });

  testWidgets('cards of an archived course never appear', (tester) async {
    final live = await seedCourse('Live');
    final archived = await seedCourse('Archived', archived: true);
    await seedCard(await seedTheme(live, 'T'), 'visible light', 'x');
    await seedCard(await seedTheme(archived, 'T'), 'hidden light', 'x');

    await openSearch(tester);
    await type(tester, 'light');

    expect(find.text('visible light'), findsOneWidget);
    expect(find.text('hidden light'), findsNothing);
  });

  testWidgets('tapping a result opens the card editor', (tester) async {
    final course = await seedCourse('Physics');
    final theme = await seedTheme(course, 'Optics');
    await seedCard(theme, 'Why the moon shines', 'reflection');

    await openSearch(tester);
    await type(tester, 'moon');
    await tester.tap(find.text('Why the moon shines'));
    await tester.pumpAndSettle();

    expect(find.byType(CardEditorScreen), findsOneWidget);
  });
}
