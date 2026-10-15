import 'package:flashcards2/domain/entities/scheduling.dart';
import 'package:flashcards2/domain/enums.dart';

/// What the rolling accuracy suggests about scheduling pressure.
enum AccuracyBand {
  /// Comfortably above target: intervals can stretch.
  widen,

  /// Inside the target window: leave the scheduler alone.
  hold,

  /// Below target: tighten and admit fewer new cards.
  tighten,

  /// Not enough history to say anything.
  insufficient,
}

/// A recommended adjustment. Advisory data, never a mutation.
class AccuracyAdvice {
  const new({
    required this.band,
    required this.sampleSize,
    this.accuracy,
    this.newCardFactor = 1,
  });

  final AccuracyBand band;
  final int sampleSize;

  /// Rolling accuracy in `[0, 1]`, or null when [band] is insufficient.
  final double? accuracy;

  /// Multiplier to apply to a course's `newCardsPerDay`. `1` means unchanged.
  final double newCardFactor;

  String get explanation => switch (band) {
    AccuracyBand.insufficient =>
      'Not enough reviews in this window to tune anything yet.',
    AccuracyBand.widen =>
      'You are recalling almost everything here, so intervals are being '
          'stretched.',
    AccuracyBand.hold =>
      'Accuracy is in the target window. Nothing is being adjusted.',
    AccuracyBand.tighten =>
      'This theme is coming back harder than target, so new-card intake is '
          'reduced and intervals are being held tighter.',
  };
}

/// Computes a rolling-accuracy advisory over recent reviews.
///
/// **This is a heuristic, not a law.** The source material cites a ~85% optimal
/// error rate for *classification* learning, and never states a mechanism that
/// maps it onto spaced repetition. Nothing here reimplements FSRS; it is a thin
/// tuning layer that reads the same review log FSRS writes, and it is described
/// to the user as a heuristic wherever it is surfaced.
///
/// The bands, with hysteresis so a single review cannot flip the decision:
///  - accuracy >= [widenAt] over [minimumSample] reviews -> widen
///  - accuracy <= [tightenAt] -> tighten
///  - between the two -> hold
///
/// Callers should apply [AccuracyAdvice.newCardFactor] only to *new-card
/// intake*. Review intervals remain FSRS's business.
class AccuracyHeuristic {
  const new({
    this.window = 30,
    this.minimumSample = 10,
    this.widenAt = 0.95,
    this.tightenAt = 0.75,
    this.tightenNewCardFactor = 0.5,
  });

  /// How many of the most recent reviews to consider.
  final int window;

  /// Below this many reviews, no advice is offered.
  final int minimumSample;

  final double widenAt;
  final double tightenAt;

  /// New-card multiplier applied when accuracy is below [tightenAt].
  final double tightenNewCardFactor;

  /// Counts a review as correct when it was not a lapse.
  ///
  /// Only [Rating.again] counts as a miss: the learner produced nothing usable.
  /// `hard` still counts as a recall, so the heuristic does not punish honest
  /// grading.
  static bool isCorrect(Rating rating) => rating != Rating.again;

  /// Reads [logs], which must be ordered newest first, as the DAO returns them.
  AccuracyAdvice advise(List<ReviewLog> logs) {
    final recent = logs.take(window).toList();
    if (recent.length < minimumSample) {
      return AccuracyAdvice(
        band: AccuracyBand.insufficient,
        sampleSize: recent.length,
      );
    }

    final correct = recent.where((log) => isCorrect(log.rating)).length;
    final accuracy = correct / recent.length;

    if (accuracy >= widenAt) {
      return AccuracyAdvice(
        band: AccuracyBand.widen,
        sampleSize: recent.length,
        accuracy: accuracy,
      );
    }
    if (accuracy <= tightenAt) {
      return AccuracyAdvice(
        band: AccuracyBand.tighten,
        sampleSize: recent.length,
        accuracy: accuracy,
        newCardFactor: tightenNewCardFactor,
      );
    }
    return AccuracyAdvice(
      band: AccuracyBand.hold,
      sampleSize: recent.length,
      accuracy: accuracy,
    );
  }
}
