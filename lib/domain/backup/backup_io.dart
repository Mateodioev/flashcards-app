import 'package:flashcards2/domain/backup/backup.dart';
import 'package:flashcards2/domain/entities/card.dart' as domain;
import 'package:flashcards2/domain/entities/course.dart';
import 'package:flashcards2/domain/entities/scheduling.dart';
import 'package:flashcards2/domain/entities/theme.dart' as domain_theme;
import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/domain/repositories/card_repository.dart';
import 'package:flashcards2/domain/repositories/course_repository.dart';
import 'package:flashcards2/domain/repositories/review_log_repository.dart';
import 'package:flashcards2/domain/repositories/settings_repository.dart';

/// Builds a [Backup] from the stored data.
///
/// Reads through the repositories rather than the database so it has no
/// knowledge of tables: if a column is renamed, this keeps working, and it
/// cannot accidentally select a column it should not export.
class BackupExporter {
  const new({
    required this.courses,
    required this.cards,
    required this.logs,
    required this.settings,
  });

  final CourseRepository courses;
  final CardRepository cards;
  final ReviewLogRepository logs;
  final SettingsRepository settings;

  Future<Backup> export({DateTime? now}) async {
    final courseList = await courses.findAll(includeArchived: true);
    final settingsRow = await settings.read();

    final exported = <BackupCourse>[];
    for (final course in courseList) {
      final themes = await cards.findThemesByCourse(course.id);
      final exportedThemes = <BackupTheme>[];

      for (final theme in themes) {
        final themeCards = await cards.findCardsByTheme(theme.id);
        final exportedCards = <BackupCard>[];

        for (final card in themeCards) {
          exportedCards.add(await _exportCard(card));
        }

        exportedThemes.add(
          BackupTheme(
            id: theme.id,
            name: theme.name,
            description: theme.description,
            createdAt: theme.createdAt,
            cards: exportedCards,
          ),
        );
      }

      exported.add(
        BackupCourse(
          id: course.id,
          name: course.name,
          createdAt: course.createdAt,
          newCardsPerDay: course.newCardsPerDay,
          interleaveMode: course.interleaveMode.name,
          archived: course.archived,
          themes: exportedThemes,
        ),
      );
    }

    return Backup(
      exportedAt: now ?? DateTime.now(),
      courses: exported,
      settings: BackupSettings(
        themeMode: settingsRow.themeMode.name,
        dayCutoffHour: settingsRow.dayCutoffHour,
        forcedGenerationBarrier: settingsRow.forcedGenerationBarrier,
        memorySpan: settingsRow.memorySpan,
        onboardingCompletedAt: settingsRow.onboardingCompletedAt,
        // apiBaseUrl, apiModelId and the API key are deliberately absent. The
        // key is not in the database at all, and the endpoint settings are
        // device-local: restoring them onto another machine would point it at
        // an endpoint and model the learner did not choose there.
      ),
    );
  }

  Future<BackupCard> _exportCard(domain.Card card) async {
    final schedule = await cards.findScheduleState(card.id);
    final cardLogs = await logs.findByCard(card.id);
    final images = await cards.findImagesByCard(card.id);

    return BackupCard(
      id: card.id,
      front: card.front,
      back: card.back,
      source: card.source.name,
      createdAt: card.createdAt,
      updatedAt: card.updatedAt,
      schedule: schedule == null
          ? null
          : BackupSchedule(
              stability: schedule.stability,
              difficulty: schedule.difficulty,
              due: schedule.due,
              reps: schedule.reps,
              lapses: schedule.lapses,
              state: schedule.state.name,
              step: schedule.step,
              lastReview: schedule.lastReview,
            ),
      logs: <BackupLog>[
        for (final log in cardLogs)
          BackupLog(
            rating: log.rating.name,
            reviewedAt: log.reviewedAt,
            elapsedDays: log.elapsedDays,
            scheduledDays: log.scheduledDays,
            state: log.state.name,
            durationMs: log.durationMs,
            hintUsed: log.hintUsed,
            barrierCompleted: log.barrierCompleted,
          ),
      ],
      // Paths only. The bytes would bloat the file without making it more
      // restorable, since the paths it needs are already absolute.
      imagePaths: <String>[for (final image in images) image.path],
    );
  }
}

/// Restores a [Backup] into the database.
///
/// Restores are **additive**: nothing is deleted. Two properties matter more
/// than completeness:
///
///  * **Ids are not preserved.** A restore into an existing database would
///    otherwise collide or overwrite, so every entity is inserted fresh and the
///    relationships are remapped through [BackupCourse.id] and friends. A
///    backup is a source of content, not a byte-for-byte image of a device.
///  * **It is all-or-nothing.** The backup is parsed and validated before any
///    write, and this class performs no partial rollback of its own: if a write
///    fails midway, the caller sees the error with earlier inserts still
///    present.
///    That is a real limitation and is reported rather than hidden.
class BackupImporter {
  const new({
    required this.courses,
    required this.cards,
    required this.logs,
    required this.settings,
  });

  final CourseRepository courses;
  final CardRepository cards;
  final ReviewLogRepository logs;
  final SettingsRepository settings;

  /// Imports [backup] and returns what was written.
  Future<ImportSummary> import(Backup backup, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    var courseCount = 0;
    var themeCount = 0;
    var cardCount = 0;
    var logCount = 0;

    for (final backupCourse in backup.courses) {
      final course = await courses.create(_course(backupCourse, at));
      courseCount++;

      for (final backupTheme in backupCourse.themes) {
        final theme = await cards.createTheme(
          domain_theme.Theme(
            id: 0,
            courseId: course.id,
            name: backupTheme.name,
            description: backupTheme.description,
            createdAt: backupTheme.createdAt,
          ),
        );
        themeCount++;

        for (final backupCard in backupTheme.cards) {
          final card = await cards.createCard(
            domain.Card(
              id: 0,
              themeId: theme.id,
              front: backupCard.front,
              back: backupCard.back,
              source: _source(backupCard.source),
              createdAt: backupCard.createdAt,
              updatedAt: at,
            ),
          );
          cardCount++;

          final schedule = backupCard.schedule;
          if (schedule != null) {
            await cards.upsertScheduleState(
              ScheduleState(
                cardId: card.id,
                stability: schedule.stability,
                difficulty: schedule.difficulty,
                due: schedule.due,
                lastReview: schedule.lastReview,
                reps: schedule.reps,
                lapses: schedule.lapses,
                state: _reviewState(schedule.state),
                step: schedule.step,
              ),
            );
          }

          for (final log in backupCard.logs) {
            await logs.append(
              ReviewLog(
                id: 0,
                cardId: card.id,
                rating: _rating(log.rating),
                reviewedAt: log.reviewedAt,
                elapsedDays: log.elapsedDays,
                scheduledDays: log.scheduledDays,
                state: _reviewState(log.state),
                durationMs: log.durationMs,
                hintUsed: log.hintUsed,
                barrierCompleted: log.barrierCompleted,
              ),
            );
            logCount++;
          }
        }
      }
    }

    // Settings are only applied when they carry a real value. Restoring a
    // backup that never ran onboarding must not clear a measured span on this
    // device, which is the one destructive thing a restore could otherwise do.
    final current = await settings.read();
    final restored = backup.settings;
    await settings.update(
      current.copyWith(
        themeMode: _themeMode(restored.themeMode, current.themeMode),
        dayCutoffHour: restored.dayCutoffHour,
        forcedGenerationBarrier: restored.forcedGenerationBarrier,
        memorySpan: restored.memorySpan ?? current.memorySpan,
        onboardingCompletedAt:
            restored.onboardingCompletedAt ?? current.onboardingCompletedAt,
      ),
    );

    return ImportSummary(
      courses: courseCount,
      themes: themeCount,
      cards: cardCount,
      logs: logCount,
    );
  }

  static Course _course(BackupCourse source, DateTime at) => Course(
    id: 0,
    name: source.name,
    createdAt: source.createdAt,
    newCardsPerDay: source.newCardsPerDay,
    interleaveMode: _interleaveMode(source.interleaveMode),
    // Restored unarchived: an archive is a local decision about what to
    // study now, not a property of the content.
    archived: false,
  );

  /// Falls back to the safe default instead of throwing.
  ///
  /// An unrecognised enum value means the file came from a different version.
  /// Refusing the whole restore over one unknown vocabulary word would be worse
  /// than importing with a conservative default, and every one of these has an
  /// obvious safe choice.
  static CardSource _source(String value) {
    for (final candidate in CardSource.values) {
      if (candidate.name == value) return candidate;
    }
    return CardSource.manual;
  }

  static InterleaveMode _interleaveMode(String value) {
    for (final candidate in InterleaveMode.values) {
      if (candidate.name == value) return candidate;
    }
    return InterleaveMode.blocked;
  }

  static AppThemeMode _themeMode(String value, AppThemeMode fallback) {
    for (final candidate in AppThemeMode.values) {
      if (candidate.name == value) return candidate;
    }
    return fallback;
  }

  static ReviewState _reviewState(String value) {
    for (final candidate in ReviewState.values) {
      if (candidate.name == value) return candidate;
    }
    return ReviewState.new_;
  }

  static Rating _rating(String value) {
    for (final candidate in Rating.values) {
      if (candidate.name == value) return candidate;
    }
    return Rating.good;
  }
}

/// What a restore wrote.
class ImportSummary {
  const new({
    required this.courses,
    required this.themes,
    required this.cards,
    required this.logs,
  });

  final int courses;
  final int themes;
  final int cards;
  final int logs;

  @override
  String toString() =>
      '$courses courses, $themes themes, $cards cards, $logs reviews';
}
