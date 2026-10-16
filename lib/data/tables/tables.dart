import 'package:drift/drift.dart';
import 'package:flashcards2/data/converters/review_state_converter.dart';
import 'package:flashcards2/domain/enums.dart';

/// Storage defaults for columns that onboarding has not yet written.
///
/// These are placeholders, not policy: the onboarding probe (T4.4) derives the
/// real per-course `newCardsPerDay` and per-course `interleaveMode`. They exist
/// so a row can be inserted before onboarding runs.
const int kDefaultNewCardsPerDay = 2;

/// Hour (0-23) at which a "day" rolls over for scheduling.
///
/// Configurable, with the near-universal 4 a.m. convention as the initial
/// value. The scheduler's day-boundary handling (T3.5) is the consumer.
const int kDefaultDayCutoffHour = 4;

/// The enum columns below use **text storage**, not integers, so a row read
/// straight out of a database browser says `interleaved` rather than `1`. That
/// is a deliberate debug-friendliness trade-off: renaming an enum member
/// changes stored data, so member names are part of the storage contract.

/// A collection of themes — the unit a learner studies.
@DataClassName('CourseRow')
class Courses extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text()();

  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();

  /// Per-course intake cap, copied from onboarding but overridable per course.
  IntColumn get newCardsPerDay =>
      integer().withDefault(const Constant(kDefaultNewCardsPerDay))();

  /// Assigned by the prior-knowledge probe, never by self-reported style.
  TextColumn get interleaveMode =>
      textEnum<InterleaveMode>().withDefault(const Constant('blocked'))();

  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

/// A themed group of cards inside a course.
@DataClassName('ThemeRow')
class Themes extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Cascade: deleting a course removes its themes, and transitively their
  /// cards, images, schedule states and logs.
  IntColumn get courseId =>
      integer().references(Courses, #id, onDelete: KeyAction.cascade)();

  TextColumn get name => text()();

  TextColumn get description => text().nullable()();

  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();
}

/// One prompt/answer pair — the atomic unit of study.
@DataClassName('CardRow')
class Cards extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get themeId =>
      integer().references(Themes, #id, onDelete: KeyAction.cascade)();

  /// Markdown with inline `$LaTeX$`, rendered by `flutter_math_fork`.
  TextColumn get front => text()();

  TextColumn get back => text()();

  TextColumn get source =>
      textEnum<CardSource>().withDefault(const Constant('manual'))();

  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();

  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();
}

/// An image attached to a card.
///
/// **Paths only.** The bytes live on the filesystem; storing them here would
/// bloat the database and make backup/export painful. The schema test asserts
/// no BLOB column exists anywhere.
@DataClassName('CardImageRow')
class CardImages extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get cardId =>
      integer().references(Cards, #id, onDelete: KeyAction.cascade)();

  /// Filesystem path to the image file — never the bytes themselves.
  TextColumn get path => text()();

  /// Display order within the card.
  IntColumn get position => integer().withDefault(const Constant(0))();

  TextColumn get caption => text().nullable()();
}

/// The scheduler's per-card state — one row per card, owned by FSRS.
///
/// This table only **stores** the FSRS quantities. The stability/difficulty
/// update math, the decay curve and the interval computation belong to the
/// scheduler port (List 3) and are deliberately absent here.
@DataClassName('ScheduleStateRow')
class ScheduleStates extends Table {
  /// The card's id doubles as this table's primary key, making the relation
  /// one-to-one rather than one-to-many.
  IntColumn get cardId =>
      integer().references(Cards, #id, onDelete: KeyAction.cascade)();

  RealColumn get stability => real().withDefault(const Constant(0))();

  RealColumn get difficulty => real().withDefault(const Constant(0))();

  DateTimeColumn get due => dateTime()();

  DateTimeColumn get lastReview => dateTime().nullable()();

  IntColumn get reps => integer().withDefault(const Constant(0))();

  IntColumn get lapses => integer().withDefault(const Constant(0))();

  /// Index into the active sub-day step list for [state].
  ///
  /// Meaningful while `learning` or `relearning`, and ignored otherwise. It is
  /// persisted because the card's next due time depends on *which* step it sits
  /// on: without it a sub-day step cannot be resumed across app restarts.
  ///
  /// Added in schema v2.
  IntColumn get step => integer().withDefault(const Constant(0))();

  /// Stored as the review-state vocabulary (`new`, `learning`, ...) via
  /// [ReviewStateConverter]; `new` is a Dart keyword and cannot be an enum
  /// member, so `textEnum` cannot express this column.
  TextColumn get state => text()
      .map(const ReviewStateConverter())
      .withDefault(const Constant('new'))();

  @override
  Set<Column<Object>> get primaryKey => {cardId};
}

/// An append-only record of every review.
///
/// This is the only input a future FSRS weight-optimization pass may read, so
/// rows are never updated or deleted — a correction is a new row, not an edit.
@DataClassName('ReviewLogRow')
class ReviewLogs extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get cardId =>
      integer().references(Cards, #id, onDelete: KeyAction.cascade)();

  TextColumn get rating => textEnum<Rating>()();

  DateTimeColumn get reviewedAt => dateTime()();

  /// Days since the previous review, as the scheduler saw them.
  RealColumn get elapsedDays => real().withDefault(const Constant(0))();

  /// Interval the scheduler assigned at review time.
  RealColumn get scheduledDays => real().withDefault(const Constant(0))();

  /// The card's state *at* the moment of review, snapshotted so the log stays
  /// interpretable even as live state moves on.
  TextColumn get state => text().map(const ReviewStateConverter())();

  /// Review latency, recorded for calibration warnings only.
  IntColumn get durationMs => integer().withDefault(const Constant(0))();

  BoolColumn get hintUsed => boolean().withDefault(const Constant(false))();

  BoolColumn get barrierCompleted =>
      boolean().withDefault(const Constant(false))();
}

/// Global application settings.
///
/// A single-row table: the primary key is pinned to `1` by a CHECK constraint,
/// so a second row cannot exist.
@DataClassName('AppSettingsRow')
class AppSettings extends Table {
  IntColumn get id => integer()();

  TextColumn get themeMode =>
      textEnum<AppThemeMode>().withDefault(const Constant('system'))();

  /// Hour (0-23) at which a "day" rolls over for scheduling.
  IntColumn get dayCutoffHour =>
      integer().withDefault(const Constant(kDefaultDayCutoffHour))();

  DateTimeColumn get onboardingCompletedAt => dateTime().nullable()();

  /// Working-memory span measured by onboarding.
  ///
  /// Null when onboarding has never been run. `newCardsPerDay` and the content
  /// chunk limit are derived from it rather than stored alongside, so there is
  /// exactly one source of truth for the learner's capacity estimate.
  ///
  /// Added in schema v3.
  IntColumn get memorySpan => integer().nullable()();

  /// Whether the Forced Generation Barrier defaults to on.
  ///
  /// Set from the calibration probe. An overconfident learner gets the barrier,
  /// because the fluency illusion is the specific failure it exists to defeat.
  ///
  /// Added in schema v3.
  BoolColumn get forcedGenerationBarrier =>
      boolean().withDefault(const Constant(false))();

  /// AI base URL. The API **key** never touches this database — it lives in
  /// `flutter_secure_storage`.
  TextColumn get apiBaseUrl => text().nullable()();

  TextColumn get apiModelId => text().nullable()();

  DateTimeColumn get apiConfiguredAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (id = 1)'];
}
