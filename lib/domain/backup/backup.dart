import 'dart:convert';

/// The on-disk backup format.
///
/// A backup exists so a learner can move devices or recover from a bad decision
/// without a cloud account. Two rules shape it:
///
///  1. **The API key is never included.** It is not in the database to begin
///     with, but [BackupSettings] is still written field by field rather than
///     copied wholesale, so a future column cannot leak into an export by
///     accident. A backup file gets copied to cloud storage, emailed, and
///     dropped in chat; a credential in one is a credential published.
///  2. **Images are referenced, not embedded.** Only the filesystem path
///     travels. Embedding bytes would bloat the file without making it
///     restorable, because the paths it needs are already absolute.
abstract final class BackupFormat {
  /// Bumped whenever the shape changes incompatibly.
  ///
  /// Readers reject an unknown version rather than guessing. A backup that
  /// silently imports wrong is worse than one that refuses, because the learner
  /// only finds out after their old data is gone.
  static const int version = 1;

  /// Marks the file as ours, so importing an unrelated JSON gives a clear error
  /// instead of a confusing one about a missing field.
  static const String magic = 'flashcards2-backup';
}

/// One course, with its themes and their cards.
class BackupCourse {
  const new({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.newCardsPerDay,
    required this.interleaveMode,
    required this.archived,
    this.themes = const <BackupTheme>[],
  });

  factory fromJson(Map<String, Object?> json) => BackupCourse(
    id: json['id']! as int,
    name: json['name']! as String,
    createdAt: DateTime.parse(json['createdAt']! as String),
    newCardsPerDay: json['newCardsPerDay']! as int,
    interleaveMode: json['interleaveMode']! as String,
    archived: json['archived']! as bool,
    themes: <BackupTheme>[
      for (final theme in (json['themes'] as List? ?? <Object?>[]))
        BackupTheme.fromJson((theme! as Map).cast<String, Object?>()),
    ],
  );

  final int id;
  final String name;
  final DateTime createdAt;
  final int newCardsPerDay;
  final String interleaveMode;
  final bool archived;
  final List<BackupTheme> themes;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'newCardsPerDay': newCardsPerDay,
    'interleaveMode': interleaveMode,
    'archived': archived,
    'themes': <Object?>[for (final theme in themes) theme.toJson()],
  };
}

class BackupTheme {
  const new({
    required this.id,
    required this.name,
    required this.createdAt,
    this.description,
    this.cards = const <BackupCard>[],
  });

  factory fromJson(Map<String, Object?> json) => BackupTheme(
    id: json['id']! as int,
    name: json['name']! as String,
    createdAt: DateTime.parse(json['createdAt']! as String),
    description: json['description'] as String?,
    cards: <BackupCard>[
      for (final card in (json['cards'] as List? ?? <Object?>[]))
        BackupCard.fromJson((card! as Map).cast<String, Object?>()),
    ],
  );

  final int id;
  final String name;
  final String? description;
  final DateTime createdAt;
  final List<BackupCard> cards;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'description': description,
    'createdAt': createdAt.toIso8601String(),
    'cards': <Object?>[for (final card in cards) card.toJson()],
  };
}

class BackupCard {
  const new({
    required this.id,
    required this.front,
    required this.back,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    this.schedule,
    this.logs = const <BackupLog>[],
    this.imagePaths = const <String>[],
  });

  factory fromJson(Map<String, Object?> json) => BackupCard(
    id: json['id']! as int,
    front: json['front']! as String,
    back: json['back']! as String,
    source: json['source']! as String,
    createdAt: DateTime.parse(json['createdAt']! as String),
    updatedAt: DateTime.parse(json['updatedAt']! as String),
    schedule: json['schedule'] == null
        ? null
        : BackupSchedule.fromJson(
            (json['schedule']! as Map).cast<String, Object?>(),
          ),
    logs: <BackupLog>[
      for (final log in (json['logs'] as List? ?? <Object?>[]))
        BackupLog.fromJson((log! as Map).cast<String, Object?>()),
    ],
    imagePaths: <String>[
      for (final path in (json['imagePaths'] as List? ?? <Object?>[]))
        path! as String,
    ],
  );

  final int id;
  final String front;
  final String back;
  final String source;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Absent for a card that has never been reviewed.
  final BackupSchedule? schedule;

  final List<BackupLog> logs;

  /// Filesystem references only. The bytes are deliberately not embedded.
  final List<String> imagePaths;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'front': front,
    'back': back,
    'source': source,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'schedule': schedule?.toJson(),
    'logs': <Object?>[for (final log in logs) log.toJson()],
    'imagePaths': imagePaths,
  };
}

/// A card's scheduling state, so a restored backup keeps its review history
/// rather than resetting everything to "new".
class BackupSchedule {
  const new({
    required this.stability,
    required this.difficulty,
    required this.due,
    required this.reps,
    required this.lapses,
    required this.state,
    required this.step,
    this.lastReview,
  });

  factory fromJson(Map<String, Object?> json) => BackupSchedule(
    stability: (json['stability']! as num).toDouble(),
    difficulty: (json['difficulty']! as num).toDouble(),
    due: DateTime.parse(json['due']! as String),
    reps: json['reps']! as int,
    lapses: json['lapses']! as int,
    state: json['state']! as String,
    step: json['step']! as int,
    lastReview: json['lastReview'] == null
        ? null
        : DateTime.parse(json['lastReview']! as String),
  );

  final double stability;
  final double difficulty;
  final DateTime due;
  final int reps;
  final int lapses;
  final String state;
  final int step;
  final DateTime? lastReview;

  Map<String, Object?> toJson() => <String, Object?>{
    'stability': stability,
    'difficulty': difficulty,
    'due': due.toIso8601String(),
    'reps': reps,
    'lapses': lapses,
    'state': state,
    'step': step,
    'lastReview': lastReview?.toIso8601String(),
  };
}

class BackupLog {
  const new({
    required this.rating,
    required this.reviewedAt,
    required this.elapsedDays,
    required this.scheduledDays,
    required this.state,
    required this.durationMs,
    required this.hintUsed,
    required this.barrierCompleted,
  });

  factory fromJson(Map<String, Object?> json) => BackupLog(
    rating: json['rating']! as String,
    reviewedAt: DateTime.parse(json['reviewedAt']! as String),
    elapsedDays: _days(json['elapsedDays']),
    scheduledDays: _days(json['scheduledDays']),
    state: json['state']! as String,
    durationMs: json['durationMs']! as int,
    hintUsed: json['hintUsed']! as bool,
    barrierCompleted: json['barrierCompleted']! as bool,
  );

  /// Reads a whole or fractional day count.
  ///
  /// The domain entity holds these as `double`, so the format does too. An
  /// earlier draft used `int` and would have truncated fractional history on
  /// export and lost it on restore — silent, and only visible as slightly wrong
  /// scheduling months later.
  static double _days(Object? value) => (value! as num).toDouble();

  final String rating;
  final DateTime reviewedAt;
  final double elapsedDays;
  final double scheduledDays;
  final String state;
  final int durationMs;
  final bool hintUsed;
  final bool barrierCompleted;

  Map<String, Object?> toJson() => <String, Object?>{
    'rating': rating,
    'reviewedAt': reviewedAt.toIso8601String(),
    'elapsedDays': elapsedDays,
    'scheduledDays': scheduledDays,
    'state': state,
    'durationMs': durationMs,
    'hintUsed': hintUsed,
    'barrierCompleted': barrierCompleted,
  };
}

/// Settings that are safe to travel.
///
/// Written field by field on purpose: `apiBaseUrl`, `apiModelId` and the key
/// are all omitted, and an allowlist means a column added later is excluded
/// until someone deliberately includes it. A denylist does the opposite.
class BackupSettings {
  const new({
    required this.themeMode,
    required this.dayCutoffHour,
    required this.forcedGenerationBarrier,
    this.memorySpan,
    this.onboardingCompletedAt,
  });

  factory fromJson(Map<String, Object?> json) => BackupSettings(
    themeMode: json['themeMode']! as String,
    dayCutoffHour: json['dayCutoffHour']! as int,
    forcedGenerationBarrier: json['forcedGenerationBarrier']! as bool,
    memorySpan: json['memorySpan'] as int?,
    onboardingCompletedAt: json['onboardingCompletedAt'] == null
        ? null
        : DateTime.parse(json['onboardingCompletedAt']! as String),
  );

  final String themeMode;
  final int dayCutoffHour;
  final bool forcedGenerationBarrier;
  final int? memorySpan;
  final DateTime? onboardingCompletedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'themeMode': themeMode,
    'dayCutoffHour': dayCutoffHour,
    'forcedGenerationBarrier': forcedGenerationBarrier,
    'memorySpan': memorySpan,
    'onboardingCompletedAt': onboardingCompletedAt?.toIso8601String(),
  };
}

/// One reminder subscription, safe to travel.
///
/// Scope is stored as the `ReminderScope` name string (`'global'`,
/// `'course'`, `'theme'`), the same convention [BackupCard] uses for its
/// source. The id is deliberately absent: restores never preserve ids, so
/// exporting one would invite code that wrongly trusts it.
class BackupReminder {
  const new({
    required this.scope,
    required this.hour,
    required this.minute,
    this.targetId,
    this.daysOfWeek,
    this.enabled = true,
  });

  factory fromJson(Map<String, Object?> json) => BackupReminder(
    scope: json['scope']! as String,
    targetId: json['targetId'] as int?,
    hour: json['hour']! as int,
    minute: json['minute']! as int,
    daysOfWeek: (json['daysOfWeek'] as List?)
        ?.map((day) => day! as int)
        .toList(),
    enabled: json['enabled'] as bool? ?? true,
  );

  final String scope;
  final int? targetId;
  final int hour;
  final int minute;
  final List<int>? daysOfWeek;
  final bool enabled;

  Map<String, Object?> toJson() => <String, Object?>{
    'scope': scope,
    'targetId': targetId,
    'hour': hour,
    'minute': minute,
    'daysOfWeek': daysOfWeek,
    'enabled': enabled,
  };
}

/// A complete backup.
class Backup {
  const new({
    required this.exportedAt,
    required this.courses,
    required this.settings,
    this.reminders = const <BackupReminder>[],
  });

  /// Parses and validates a backup file.
  ///
  /// Throws [BackupFormatException] with a readable reason when unusable.
  /// Validation is **all-or-nothing and happens before any write**: the caller
  /// must be able to trust that a successfully parsed backup can be applied, so
  /// a malformed file can never leave a half-imported database.
  factory decode(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw BackupFormatException('This file is not valid JSON: ${e.message}');
    }

    if (decoded is! Map) {
      throw const BackupFormatException(
        'This file does not contain a backup object.',
      );
    }
    final json = decoded.cast<String, Object?>();

    if (json['format'] != BackupFormat.magic) {
      throw const BackupFormatException(
        'This file was not created by this app.',
      );
    }

    final version = json['version'];
    if (version is! int) {
      throw const BackupFormatException('The backup has no version number.');
    }
    if (version > BackupFormat.version) {
      throw BackupFormatException(
        'This backup was made by a newer version of the app '
        '(format $version, this app reads ${BackupFormat.version}). Update '
        'the app first.',
      );
    }

    final rawCourses = json['courses'];
    if (rawCourses is! List) {
      throw const BackupFormatException('The backup has no course list.');
    }

    try {
      return Backup(
        exportedAt: json['exportedAt'] is String
            ? DateTime.parse(json['exportedAt']! as String)
            : DateTime.now(),
        courses: <BackupCourse>[
          for (final course in rawCourses)
            BackupCourse.fromJson((course! as Map).cast<String, Object?>()),
        ],
        settings: BackupSettings.fromJson(
          (json['settings']! as Map).cast<String, Object?>(),
        ),
        // Optional since format version 1: backups written before reminders
        // existed decode as an empty list, so the version does not need to
        // move for this additive key.
        reminders: <BackupReminder>[
          for (final reminder
              in (json['reminders'] as List? ?? <Object?>[]))
            BackupReminder.fromJson(
              (reminder! as Map).cast<String, Object?>(),
            ),
        ],
      );
    } on BackupFormatException {
      rethrow;
    } on Object catch (e) {
      // A missing or mistyped field lands here. The message must be something a
      // learner can act on, so the raw exception text is NOT included: it
      // reads like `type 'String' is not a subtype of type 'int' in type
      // cast`, which describes the parser's internals and tells the reader
      // nothing about what to do. The detail is still available to a developer
      // through the exception's [cause].
      throw BackupFormatException(
        'The backup is incomplete or damaged, so nothing was imported. It may '
        'have been cut short while copying, or created by a different version '
        'of the app.',
        cause: e,
      );
    }
  }

  final DateTime exportedAt;
  final List<BackupCourse> courses;
  final BackupSettings settings;

  /// Every exported reminder subscription, target-scoped ones included (they
  /// are skipped on restore by the importer in backup_io.dart).
  final List<BackupReminder> reminders;

  /// How many cards the backup holds, for a confirmation message.
  int get cardCount => courses.fold(
    0,
    (total, course) =>
        total + course.themes.fold(0, (n, theme) => n + theme.cards.length),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'format': BackupFormat.magic,
    'version': BackupFormat.version,
    'exportedAt': exportedAt.toIso8601String(),
    'settings': settings.toJson(),
    'courses': <Object?>[for (final course in courses) course.toJson()],
    'reminders': <Object?>[for (final reminder in reminders) reminder.toJson()],
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// A backup that could not be read, with a reason worth showing a learner.
class BackupFormatException implements Exception {
  const new(this.message, {this.cause});

  final String message;

  /// The underlying error, kept for developers.
  ///
  /// Deliberately separate from [message]: the user-facing text has to be
  /// actionable, while this retains the detail needed to debug a report.
  final Object? cause;

  @override
  String toString() => message;
}
