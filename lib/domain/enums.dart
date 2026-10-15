// Domain enums. Pure Dart: no Drift, no Flutter.
//
// These live in `domain/` because they are vocabulary the app reasons about,
// not storage details. The data layer decides how they are persisted.

/// How a course's cards are sequenced within a session.
///
/// `blocked` groups one theme at a time (novice practice); `interleaved` mixes
/// themes (expert practice). Assigned per course by the onboarding
/// prior-knowledge probe, per the expertise-reversal effect.
enum InterleaveMode { blocked, interleaved }

/// Where a card came from.
///
/// `aiGenerated` marks cards produced by the image -> flashcards pipeline,
/// which only persist after passing the mandatory review screen.
enum CardSource { manual, aiGenerated }

/// The scheduler's lifecycle stage for a card.
///
/// The first member is spelled `new_` because `new` is a reserved word in
/// Dart, so no enum member can carry that identifier. The data layer maps
/// `new_` to the exact text `new` on the way to SQLite; the database keeps the
/// vocabulary the design specifies, and the Dart-only workaround never leaks
/// into storage.
enum ReviewState { new_, learning, review, relearning }

/// The four-point review grade.
///
/// The self-grade is the grade. Behavioral signals (latency, hints, barrier)
/// are recorded for calibration warnings only and never override this value.
enum Rating { again, hard, good, easy }

/// The persisted theme preference.
enum AppThemeMode { system, light, dark }
