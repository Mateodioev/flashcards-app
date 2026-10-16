import 'package:flashcards2/domain/onboarding/calibration.dart';
import 'package:flashcards2/domain/onboarding/memory_span.dart';
import 'package:flashcards2/domain/onboarding/prior_knowledge.dart';

/// Everything one onboarding run produces.
///
/// The span session sets a **global** default; the prior-knowledge probe sets a
/// **per-course** policy. That split is deliberate, and it is how this design
/// closes the gap in the source material, whose short audit did not measure
/// prior knowledge at all while its decision matrix depended on it.
class OnboardingResult {
  const new({
    required this.span,
    required this.newCardsPerDay,
    required this.contentChunkLimit,
    required this.forcedGenerationBarrierDefault,
    required this.calibrationVerdict,
    required this.wasSkipped,
  });

  /// The defaults applied when the learner skips onboarding.
  ///
  /// Skipping must still produce a complete, usable configuration — never nulls
  /// and never a half-applied state.
  factory skipped() {
    const span = MemorySpanDefaults.fallbackSpan;
    return OnboardingResult(
      span: span,
      newCardsPerDay: MemorySpanDefaults.newCardsPerDay(span),
      contentChunkLimit: MemorySpanDefaults.contentChunkLimit(span),
      forcedGenerationBarrierDefault: false,
      calibrationVerdict: CalibrationVerdict.insufficient,
      wasSkipped: true,
    );
  }

  final int span;
  final int newCardsPerDay;

  /// Maximum number of items a single card should ask the learner to hold.
  ///
  /// Grounded in Cowan's `4 ± 1` bound rather than this learner's span, so it
  /// stays within the evidence even when a span comes out unusually high.
  final int contentChunkLimit;

  final bool forcedGenerationBarrierDefault;
  final CalibrationVerdict calibrationVerdict;
  final bool wasSkipped;
}

/// Assembles the three probes into the settings onboarding writes.
abstract final class Onboarding {
  /// Combines a completed span session and calibration probe.
  ///
  /// [calibration] is optional: a learner may finish the span probe and stop.
  /// An absent calibration leaves the barrier at its default rather than
  /// guessing an overconfidence verdict, because guessing would turn on a
  /// behaviour-changing barrier on no evidence.
  static OnboardingResult combine({
    required MemorySpanOutcome spanOutcome,
    CalibrationResult? calibration,
  }) {
    final span = spanOutcome.span <= 0
        ? MemorySpanDefaults.fallbackSpan
        : spanOutcome.span;

    return OnboardingResult(
      span: span,
      newCardsPerDay: MemorySpanDefaults.newCardsPerDay(span),
      contentChunkLimit: MemorySpanDefaults.contentChunkLimit(span),
      forcedGenerationBarrierDefault:
          calibration?.forcedGenerationBarrierDefault ?? false,
      calibrationVerdict:
          calibration?.verdict ?? CalibrationVerdict.insufficient,
      wasSkipped: false,
    );
  }

  /// The per-course policy for a probe, capped by the global ceiling.
  static CoursePolicy coursePolicy(
    PriorKnowledgeProbe probe,
    OnboardingResult result,
  ) {
    return PriorKnowledgePolicy.policyFor(
      probe,
      globalNewCardsPerDay: result.newCardsPerDay,
    );
  }
}
