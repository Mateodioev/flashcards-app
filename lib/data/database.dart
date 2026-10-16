import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flashcards2/data/converters/review_state_converter.dart';
import 'package:flashcards2/data/daos/card_dao.dart';
import 'package:flashcards2/data/daos/course_dao.dart';
import 'package:flashcards2/data/daos/review_log_dao.dart';
import 'package:flashcards2/data/daos/settings_dao.dart';
import 'package:flashcards2/data/tables/tables.dart';
// The generated `database.g.dart` is a `part of` this library and references
// the domain enums used by `textEnum` columns directly, so this import is
// required here even though no hand-written code in this file names them.
import 'package:flashcards2/domain/enums.dart';
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// The application's SQLite database.
///
/// Opens through `drift_flutter`, which resolves the platform file location
/// and spins up a background isolate on Android. Tests inject their own
/// in-memory [QueryExecutor] through the constructor instead, so nothing here
/// is required to run a unit test.
@DriftDatabase(
  tables: [
    Courses,
    Themes,
    Cards,
    CardImages,
    ScheduleStates,
    ReviewLogs,
    AppSettings,
  ],
  daos: [CourseDao, CardDao, ReviewLogDao, SettingsDao],
)
class AppDatabase extends _$AppDatabase {
  /// Opens the database.
  ///
  /// When [executor] is omitted the on-disk database is opened. The database
  /// lives in the application *support* directory rather than the documents
  /// directory: it is app-private state, not user-facing content, and on
  /// Android it must not be swept into a user-visible backup.
  new([QueryExecutor? executor]) : super(executor ?? _openConnection());

  /// The default number of new cards a course admits per day.
  ///
  /// A placeholder for a value onboarding (T4.4) is expected to override.
  static const int defaultNewCardsPerDay = kDefaultNewCardsPerDay;

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) => m.createAll(),
      onUpgrade: (m, from, to) async {
        // v2 added `schedule_states.step`, the persisted index into the sub-day
        // learning/relearning step list. Defaulting it to 0 puts every existing
        // card on the first step, which is the correct place for a card whose
        // step index was never recorded.
        if (from < 2) {
          await m.addColumn(scheduleStates, scheduleStates.step);
        }
        // v3 added the onboarding outputs. `memory_span` stays null for an
        // existing install, which correctly means "onboarding has not run";
        // writing a default span would fabricate a measurement.
        if (from < 3) {
          await m.addColumn(appSettings, appSettings.memorySpan);
          await m.addColumn(appSettings, appSettings.forcedGenerationBarrier);
        }
      },
      beforeOpen: (details) async {
        // Off by default in SQLite; the ON DELETE CASCADE clauses on every
        // child table are inert without it. This must run before any query.
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'flashcards2',
      native: const DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    );
  }
}
