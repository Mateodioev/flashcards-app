import 'package:flashcards2/domain/enums.dart';

/// The scheduler's per-card state.
///
/// This is a *storage* view of the FSRS quantities. The math that produces and
/// advances these values belongs to the scheduler port (List 3) and is
/// deliberately absent from the domain entities at this stage.
class ScheduleState {
  const new({
    required this.cardId,
    required this.stability,
    required this.difficulty,
    required this.due,
    required this.reps,
    required this.lapses,
    required this.state,
    this.step = 0,
    this.lastReview,
  });

  final int cardId;
  final double stability;
  final double difficulty;
  final DateTime due;
  final DateTime? lastReview;
  final int reps;
  final int lapses;
  final ReviewState state;

  /// Index into the active sub-day step list for [state].
  ///
  /// Meaningful while `learning` or `relearning`; ignored otherwise. Persisted
  /// so a card can resume mid-step across app restarts.
  final int step;
}

/// An append-only record of one review.
///
/// Never updated or deleted: it is the historical input a future FSRS
/// weight-optimization pass may read.
class ReviewLog {
  const new({
    required this.id,
    required this.cardId,
    required this.rating,
    required this.reviewedAt,
    required this.elapsedDays,
    required this.scheduledDays,
    required this.state,
    required this.durationMs,
    required this.hintUsed,
    required this.barrierCompleted,
  });

  final int id;
  final int cardId;
  final Rating rating;
  final DateTime reviewedAt;
  final double elapsedDays;
  final double scheduledDays;

  /// The card's state at the moment of review, snapshotted.
  final ReviewState state;

  final int durationMs;
  final bool hintUsed;
  final bool barrierCompleted;
}

/// Global application settings.
///
/// The API key is intentionally absent: it lives in secure storage and never
/// reaches SQLite.
class AppSettings {
  const new({
    required this.id,
    required this.themeMode,
    required this.dayCutoffHour,
    this.memorySpan,
    this.forcedGenerationBarrier = false,
    this.onboardingCompletedAt,
    this.apiBaseUrl,
    this.apiModelId,
    this.apiConfiguredAt,
  });

  final int id;
  final AppThemeMode themeMode;

  /// Hour (0-23) at which a "day" rolls over for scheduling.
  final int dayCutoffHour;

  /// Working-memory span from onboarding, or null if it has never run.
  ///
  /// The daily new-card target and the content chunk limit are **derived** from
  /// this, not stored, so there is one source of truth for capacity.
  final int? memorySpan;

  /// Whether the Forced Generation Barrier defaults to on.
  final bool forcedGenerationBarrier;

  final DateTime? onboardingCompletedAt;
  final String? apiBaseUrl;
  final String? apiModelId;
  final DateTime? apiConfiguredAt;

  /// The only settings row there can be.
  static const int singletonId = 1;

  /// A copy with selected fields replaced.
  ///
  /// Present because the settings row is updated one field at a time — theme
  /// mode, day cutoff, onboarding results — and rebuilding all nine fields at
  /// every call site is how a field silently reverts.
  AppSettings copyWith({
    AppThemeMode? themeMode,
    int? dayCutoffHour,
    int? memorySpan,
    bool? forcedGenerationBarrier,
    DateTime? onboardingCompletedAt,
    String? apiBaseUrl,
    String? apiModelId,
    DateTime? apiConfiguredAt,
  }) {
    return AppSettings(
      id: singletonId,
      themeMode: themeMode ?? this.themeMode,
      dayCutoffHour: dayCutoffHour ?? this.dayCutoffHour,
      memorySpan: memorySpan ?? this.memorySpan,
      forcedGenerationBarrier:
          forcedGenerationBarrier ?? this.forcedGenerationBarrier,
      onboardingCompletedAt:
          onboardingCompletedAt ?? this.onboardingCompletedAt,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      apiModelId: apiModelId ?? this.apiModelId,
      apiConfiguredAt: apiConfiguredAt ?? this.apiConfiguredAt,
    );
  }
}
