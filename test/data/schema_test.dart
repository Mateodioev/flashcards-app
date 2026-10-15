import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flashcards2/data/daos/settings_dao.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/data/tables/tables.dart';
import 'package:flashcards2/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

import '../generated_migrations/schema.dart';

/// Proves the v1 schema is real, not merely declared.
///
/// Two layers of proof:
///  - the tables physically exist in a freshly created database, carry no BLOB
///    column, and their foreign keys cascade as the design requires;
///  - an insert -> read round-trip walks the full hierarchy,
///    course -> theme -> card -> card_image -> schedule_state -> review_log.
///
/// The round-trip matters because codegen can happily emit a table that the
/// runtime never creates, or create it with the wrong constraints. Opening a
/// real in-memory database and writing through it is the only way to know.
void main() {
  // The snapshot test opens a second `AppDatabase` over the generated v1
  // schema on purpose, which is exactly the "multiple databases" situation
  // drift warns about. Those two instances never share an executor.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;

  setUp(() {
    // The injected in-memory executor keeps the test hermetic and fast, and
    // exercises the same code path as the on-disk database minus the file.
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('every v1 table exists in sqlite_master', () async {
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final names = rows.map((row) => row.read<String>('name')).toSet();

    expect(
      names,
      containsAll(<String>[
        'courses',
        'themes',
        'cards',
        'card_images',
        'schedule_states',
        'review_logs',
        'app_settings',
      ]),
    );
  });

  test('no BLOB column exists anywhere in the schema', () async {
    final tables = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();

    for (final table in tables) {
      final name = table.read<String>('name');
      final columns = await db.customSelect('PRAGMA table_info("$name")').get();
      for (final column in columns) {
        expect(
          column.read<String>('type').toUpperCase(),
          isNot(contains('BLOB')),
          reason:
              '$name.${column.read<String>('name')} must hold a path, '
              'never image bytes',
        );
      }
    }
  });

  test('round-trips the course -> theme -> card -> image -> schedule '
      '-> review_log hierarchy', () async {
    final courseId = await db
        .into(db.courses)
        .insert(CoursesCompanion.insert(name: 'Biology'));
    final themeId = await db
        .into(db.themes)
        .insert(
          ThemesCompanion.insert(courseId: courseId, name: 'Cell biology'),
        );
    final cardId = await db
        .into(db.cards)
        .insert(
          CardsCompanion.insert(
            themeId: themeId,
            front: r'What is $2+2$?',
            back: 'Four',
          ),
        );
    await db
        .into(db.cardImages)
        .insert(
          CardImagesCompanion.insert(cardId: cardId, path: '/tmp/diagram.png'),
        );
    await db
        .into(db.scheduleStates)
        .insert(
          ScheduleStatesCompanion.insert(
            cardId: Value(cardId),
            due: DateTime(2026),
          ),
        );
    await db
        .into(db.reviewLogs)
        .insert(
          ReviewLogsCompanion.insert(
            cardId: cardId,
            rating: Rating.good,
            reviewedAt: DateTime(2026),
            state: ReviewState.new_,
          ),
        );

    final course = await db.courses.select().getSingle();
    final theme = await db.themes.select().getSingle();
    final card = await db.cards.select().getSingle();
    final image = await db.cardImages.select().getSingle();
    final schedule = await db.scheduleStates.select().getSingle();
    final log = await db.reviewLogs.select().getSingle();

    expect(course.name, 'Biology');
    expect(course.newCardsPerDay, kDefaultNewCardsPerDay);
    expect(course.interleaveMode, InterleaveMode.blocked);
    expect(course.archived, isFalse);

    expect(theme.courseId, courseId);
    expect(theme.description, isNull);

    expect(card.themeId, themeId);
    expect(card.front, r'What is $2+2$?');
    expect(card.source, CardSource.manual);

    expect(image.cardId, cardId);
    expect(image.position, 0);
    expect(image.caption, isNull);

    expect(schedule.cardId, cardId);
    // Nothing computes the FSRS values yet; the columns exist and start at
    // zero, which is the whole contract at this stage.
    expect(schedule.stability, 0);
    expect(schedule.difficulty, 0);
    expect(schedule.reps, 0);
    expect(schedule.lapses, 0);
    expect(schedule.state, ReviewState.new_);
    expect(schedule.lastReview, isNull);

    expect(log.cardId, cardId);
    expect(log.rating, Rating.good);
    expect(log.state, ReviewState.new_);
    expect(log.hintUsed, isFalse);
    expect(log.barrierCompleted, isFalse);
  });

  test('enum columns store their readable names, not indices', () async {
    final courseId = await db
        .into(db.courses)
        .insert(
          CoursesCompanion.insert(
            name: 'Chemistry',
            interleaveMode: const Value(InterleaveMode.interleaved),
          ),
        );
    final themeId = await db
        .into(db.themes)
        .insert(ThemesCompanion.insert(courseId: courseId, name: 'Bonds'));
    final cardId = await db
        .into(db.cards)
        .insert(CardsCompanion.insert(themeId: themeId, front: 'a', back: 'b'));
    await db
        .into(db.scheduleStates)
        .insert(
          ScheduleStatesCompanion.insert(
            cardId: Value(cardId),
            due: DateTime(2026),
          ),
        );

    final course = await db
        .customSelect(
          'SELECT interleave_mode FROM courses WHERE id = ?',
          variables: [Variable<int>(courseId)],
        )
        .getSingle();
    final state = await db
        .customSelect(
          'SELECT state FROM schedule_states WHERE card_id = ?',
          variables: [Variable<int>(cardId)],
        )
        .getSingle();

    expect(course.read<String>('interleave_mode'), 'interleaved');
    // The storage contract says `new`, not the Dart-only `new_` workaround.
    expect(state.read<String>('state'), 'new');
  });

  test('deleting a course cascades through themes, cards and logs', () async {
    final courseId = await db
        .into(db.courses)
        .insert(CoursesCompanion.insert(name: 'History'));
    final themeId = await db
        .into(db.themes)
        .insert(ThemesCompanion.insert(courseId: courseId, name: 'Modern'));
    final cardId = await db
        .into(db.cards)
        .insert(CardsCompanion.insert(themeId: themeId, front: 'a', back: 'b'));
    await db
        .into(db.reviewLogs)
        .insert(
          ReviewLogsCompanion.insert(
            cardId: cardId,
            rating: Rating.again,
            reviewedAt: DateTime(2026),
            state: ReviewState.learning,
          ),
        );

    await (db.delete(db.courses)..where((c) => c.id.equals(courseId))).go();

    expect(await db.themes.select().get(), isEmpty);
    expect(await db.cards.select().get(), isEmpty);
    expect(await db.reviewLogs.select().get(), isEmpty);
  });

  test('card deletion cascades to images and schedule states', () async {
    final courseId = await db
        .into(db.courses)
        .insert(CoursesCompanion.insert(name: 'Physics'));
    final themeId = await db
        .into(db.themes)
        .insert(ThemesCompanion.insert(courseId: courseId, name: 'Optics'));
    final cardId = await db
        .into(db.cards)
        .insert(CardsCompanion.insert(themeId: themeId, front: 'a', back: 'b'));
    await db
        .into(db.cardImages)
        .insert(CardImagesCompanion.insert(cardId: cardId, path: '/tmp/x.png'));
    await db
        .into(db.scheduleStates)
        .insert(
          ScheduleStatesCompanion.insert(
            cardId: Value(cardId),
            due: DateTime(2026),
          ),
        );

    await (db.delete(db.cards)..where((c) => c.id.equals(cardId))).go();

    expect(await db.cardImages.select().get(), isEmpty);
    expect(await db.scheduleStates.select().get(), isEmpty);
  });

  test('app_settings is constrained to a single row', () async {
    final settings = await db.settingsDao.readOrCreate();
    expect(settings.id, SettingsDao.singletonId);
    expect(settings.themeMode, AppThemeMode.system);
    expect(settings.dayCutoffHour, kDefaultDayCutoffHour);

    // A second row must be rejected by the `CHECK (id = 1)` constraint, not
    // silently accepted.
    await expectLater(
      db.into(db.appSettings).insert(const AppSettingsCompanion(id: Value(2))),
      throwsA(isA<SqliteException>()),
    );
    expect(await db.appSettings.select().get(), hasLength(1));
  });

  test('schema version is 1 and the migration strategy is explicit', () async {
    expect(db.schemaVersion, 1);
    expect(db.migration.beforeOpen, isNotNull);
    expect(GeneratedHelper.versions, [1]);
  });

  test('a fresh database matches the committed v1 snapshot', () async {
    // `GeneratedHelper` is generated from the committed
    // `drift_schemas/drift_schema_v1.json`. Opening a database from that
    // snapshot and validating it compares the *snapshot* against the schema
    // the table declarations generate from scratch — so this fails if the
    // committed JSON and the Drift tables ever drift apart.
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(1);
    final opened = AppDatabase(schema.newConnection());

    await opened.validateDatabaseSchema();

    await opened.close();
  });
}
