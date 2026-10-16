import 'package:flashcards2/domain/enums.dart';

/// A quick check of how much of a course's material the learner already holds.
class PriorKnowledgeProbe {
  const new({
    required this.selfRating,
    required this.sampleCardsAttempted,
    required this.sampleCardsCorrect,
  });

  /// The learner's own estimate, in `[0, 1]`.
  ///
  /// Deliberately only one of two inputs: the source material is emphatic that
  /// self-report is inflated by the fluency illusion, so it is checked against
  /// performance rather than trusted.
  final double selfRating;

  final int sampleCardsAttempted;
  final int sampleCardsCorrect;

  double get observedAccuracy {
    if (sampleCardsAttempted == 0) return 0;
    return sampleCardsCorrect / sampleCardsAttempted;
  }

  /// Whether the learner looks like a novice in this course.
  ///
  /// Novices get blocked practice and worked examples; experts interleave.
  /// The expertise-reversal effect means applying the wrong one actively hurts,
  /// so this routes rather than personalises.
  ///
  /// **Performance leads whenever there is any.** Self-report is checked
  /// against performance rather than trusted, because the fluency illusion
  /// inflates it — and that cuts both ways: a learner who rates themselves
  /// poorly but recalls every sample is not treated as a novice. Self-rating is
  /// consulted only when nothing was attempted and there is nothing else to go
  /// on.
  bool get isNovice {
    if (sampleCardsAttempted > 0) {
      return observedAccuracy < 0.5;
    }
    return selfRating < 0.4;
  }
}

/// A course's initial scheduling policy, derived from its probe.
class CoursePolicy {
  const new({required this.interleaveMode, required this.newCardsPerDay});

  final InterleaveMode interleaveMode;
  final int newCardsPerDay;
}

/// Turns a probe into a course policy.
///
/// **Deliberately not a learning-style classifier.** It asks how much the
/// learner already knows about this specific material, which is a valid
/// dimension of difference and the one the expertise-reversal evidence acts on.
/// It never asks how they prefer to be taught.
abstract final class PriorKnowledgePolicy {
  /// New cards per day for a novice: fewer, because a novice accumulates
  /// backlog faster and bottlenecked practice is what stalls them.
  static const int noviceNewCardsPerDay = 5;

  /// New cards per day for someone with existing knowledge in the course.
  static const int nonNoviceNewCardsPerDay = 10;

  static CoursePolicy policyFor(
    PriorKnowledgeProbe probe, {
    required int globalNewCardsPerDay,
  }) {
    final novice = probe.isNovice;
    final base = novice ? noviceNewCardsPerDay : nonNoviceNewCardsPerDay;
    return CoursePolicy(
      // Novices get blocked practice: interleaving before the underlying rule
      // is acquired is documented as harmful, not merely less effective.
      interleaveMode: novice
          ? InterleaveMode.blocked
          : InterleaveMode.interleaved,
      // Never exceed the global ceiling derived from the span session.
      newCardsPerDay: base < globalNewCardsPerDay ? base : globalNewCardsPerDay,
    );
  }
}
