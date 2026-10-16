import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/domain/onboarding/calibration.dart';
import 'package:flashcards2/domain/onboarding/memory_span.dart';
import 'package:flashcards2/domain/onboarding/onboarding.dart';
import 'package:flashcards2/domain/onboarding/prior_knowledge.dart';
import 'package:flutter_test/flutter_test.dart';

/// Repeatedly answers [answer] until the session ends, and reports the outcome.
MemorySpanOutcome runSpan(MemorySpanSession session, bool Function() answer) {
  var guard = 0;
  while (!session.isComplete && guard < 100) {
    session.submit(
      answer()
          ? session.current.digits
          : <int>[for (final d in session.current.digits) (d % 9) + 1],
    );
    guard++;
  }
  return session.outcome;
}

void main() {
  group('MemorySpanSession', () {
    test('climbs while answers are correct and stops at the ceiling', () {
      final session = MemorySpanSession(seed: 1, maxLength: 5);
      final outcome = runSpan(session, () => true);
      expect(outcome.span, 5);
      expect(session.isComplete, isTrue);
    });

    test('stops after the allowed retries at one length', () {
      final session = MemorySpanSession(seed: 1);
      final outcome = runSpan(session, () => false);
      expect(outcome.span, 0);
      expect(
        session.trialsTaken,
        2,
        reason: 'one attempt plus one retry, then stop',
      );
    });

    test('a wrong order is a failure, not a pass', () {
      const trial = MemorySpanTrial(digits: <int>[1, 2, 3]);
      expect(trial.isCorrect(<int>[1, 2, 3]), isTrue);
      expect(trial.isCorrect(<int>[3, 2, 1]), isFalse);
      expect(trial.isCorrect(<int>[1, 2]), isFalse);
      expect(trial.isCorrect(<int>[1, 2, 3, 4]), isFalse);
    });

    test('the same seed produces the same sequence', () {
      final a = MemorySpanSession(seed: 42);
      final b = MemorySpanSession(seed: 42);
      expect(a.current.digits, b.current.digits);
    });

    test('a different seed produces a different sequence', () {
      final a = MemorySpanSession(seed: 1);
      final b = MemorySpanSession(seed: 2);
      expect(a.current.digits, isNot(b.current.digits));
    });

    test('the sequence does not repeat a single digit', () {
      // Guards against the generator being seeded per digit, which would emit
      // one repeated value rather than a sequence.
      final session = MemorySpanSession(seed: 7, startLength: 5);
      expect(session.current.digits.toSet().length, greaterThan(1));
    });

    test('submitting after completion throws rather than corrupting state', () {
      final session = MemorySpanSession(seed: 1, maxLength: 3);
      runSpan(session, () => true);
      expect(session.isComplete, isTrue);
      expect(() => session.submit(<int>[1, 2, 3]), throwsStateError);
    });

    test('the retry presents a fresh sequence at the same length', () {
      final session = MemorySpanSession(seed: 3);
      final first = session.current.digits;
      session.submit(<int>[for (final d in first) (d % 9) + 1]);
      expect(session.isComplete, isFalse);
      expect(session.current.length, first.length);
      expect(session.current.digits, isNot(first));
    });
  });

  group('MemorySpanDefaults', () {
    test('chunk limit stays inside Cowan 4 plus or minus 1', () {
      for (final span in <int>[1, 2, 3, 4, 5, 9]) {
        final limit = MemorySpanDefaults.contentChunkLimit(span);
        expect(limit, inInclusiveRange(3, 5));
      }
    });

    test('new cards per day never decreases as span grows', () {
      var previous = 0;
      for (var span = 1; span <= 9; span++) {
        final value = MemorySpanDefaults.newCardsPerDay(span);
        expect(value, greaterThanOrEqualTo(previous));
        previous = value;
      }
    });
  });

  group('CalibrationProbe', () {
    CalibrationProbe probe() => const CalibrationProbe();

    test('reports insufficient below the minimum sample', () {
      final result = probe()
          .withTrial(const CalibrationTrial(predicted: 1, actual: 0))
          .result;
      expect(result.verdict, CalibrationVerdict.insufficient);
      expect(
        result.forcedGenerationBarrierDefault,
        isFalse,
        reason: 'no evidence must not switch on a behaviour-changing barrier',
      );
    });

    test('overconfidence enables the forced generation barrier', () {
      final result = probe()
          .withTrial(const CalibrationTrial(predicted: 1, actual: 0.4))
          .withTrial(const CalibrationTrial(predicted: 0.9, actual: 0.5))
          .withTrial(const CalibrationTrial(predicted: 0.8, actual: 0.3))
          .result;
      expect(result.verdict, CalibrationVerdict.overconfident);
      expect(
        result.forcedGenerationBarrierDefault,
        isTrue,
        reason: 'the barrier exists precisely for the fluency illusion',
      );
      expect(result.meanBias, greaterThan(0));
    });

    test('accurate self-assessment leaves the barrier off', () {
      final result = probe()
          .withTrial(const CalibrationTrial(predicted: 0.6, actual: 0.6))
          .withTrial(const CalibrationTrial(predicted: 0.7, actual: 0.65))
          .withTrial(const CalibrationTrial(predicted: 0.5, actual: 0.5))
          .result;
      expect(result.verdict, CalibrationVerdict.calibrated);
      expect(result.forcedGenerationBarrierDefault, isFalse);
    });

    test('underconfidence is distinguished from calibration', () {
      final result = probe()
          .withTrial(const CalibrationTrial(predicted: 0.2, actual: 0.8))
          .withTrial(const CalibrationTrial(predicted: 0.3, actual: 0.9))
          .withTrial(const CalibrationTrial(predicted: 0.1, actual: 0.7))
          .result;
      expect(result.verdict, CalibrationVerdict.underconfident);
      expect(result.meanBias, lessThan(0));
    });

    test('bias sign convention: positive means predicted too high', () {
      const over = CalibrationTrial(predicted: 0.9, actual: 0.5);
      const under = CalibrationTrial(predicted: 0.3, actual: 0.8);
      expect(over.bias, greaterThan(0));
      expect(under.bias, lessThan(0));
    });
  });

  group('PriorKnowledgeProbe', () {
    test(
      'poor sample performance marks a novice despite a high self-rating',
      () {
        const probe = PriorKnowledgeProbe(
          selfRating: 0.95,
          sampleCardsAttempted: 4,
          sampleCardsCorrect: 1,
        );
        expect(
          probe.isNovice,
          isTrue,
          reason: 'performance leads; self-report is inflated by fluency',
        );
      },
    );

    test(
      'strong sample performance marks a non-novice despite a low rating',
      () {
        const probe = PriorKnowledgeProbe(
          selfRating: 0.2,
          sampleCardsAttempted: 4,
          sampleCardsCorrect: 4,
        );
        expect(probe.isNovice, isFalse);
      },
    );

    test('a low self-rating alone is enough when nothing was attempted', () {
      const probe = PriorKnowledgeProbe(
        selfRating: 0.1,
        sampleCardsAttempted: 0,
        sampleCardsCorrect: 0,
      );
      expect(probe.isNovice, isTrue);
    });

    test('novices get blocked practice, non-novices interleaved', () {
      const novice = PriorKnowledgeProbe(
        selfRating: 0.1,
        sampleCardsAttempted: 0,
        sampleCardsCorrect: 0,
      );
      const expert = PriorKnowledgeProbe(
        selfRating: 0.9,
        sampleCardsAttempted: 4,
        sampleCardsCorrect: 4,
      );
      const result = OnboardingResult(
        span: 4,
        newCardsPerDay: 8,
        contentChunkLimit: 4,
        forcedGenerationBarrierDefault: false,
        calibrationVerdict: CalibrationVerdict.calibrated,
        wasSkipped: false,
      );

      expect(
        Onboarding.coursePolicy(novice, result).interleaveMode,
        InterleaveMode.blocked,
      );
      expect(
        Onboarding.coursePolicy(expert, result).interleaveMode,
        InterleaveMode.interleaved,
      );
    });

    test('a course policy never exceeds the global new-card ceiling', () {
      const expert = PriorKnowledgeProbe(
        selfRating: 1,
        sampleCardsAttempted: 4,
        sampleCardsCorrect: 4,
      );
      const lowCeiling = OnboardingResult(
        span: 2,
        newCardsPerDay: 3,
        contentChunkLimit: 3,
        forcedGenerationBarrierDefault: false,
        calibrationVerdict: CalibrationVerdict.calibrated,
        wasSkipped: false,
      );
      final policy = Onboarding.coursePolicy(expert, lowCeiling);
      expect(policy.newCardsPerDay, lessThanOrEqualTo(3));
    });
  });

  group('OnboardingResult', () {
    test('skipping produces a complete configuration, never nulls', () {
      final skipped = OnboardingResult.skipped();
      expect(skipped.wasSkipped, isTrue);
      expect(skipped.span, MemorySpanDefaults.fallbackSpan);
      expect(skipped.newCardsPerDay, greaterThan(0));
      expect(skipped.contentChunkLimit, inInclusiveRange(3, 5));
      expect(skipped.forcedGenerationBarrierDefault, isFalse);
      expect(skipped.calibrationVerdict, CalibrationVerdict.insufficient);
    });

    test('a zero span falls back rather than producing zero cards', () {
      final result = Onboarding.combine(
        spanOutcome: const MemorySpanOutcome(span: 0, trialsTaken: 2),
      );
      expect(result.span, MemorySpanDefaults.fallbackSpan);
      expect(result.newCardsPerDay, greaterThan(0));
    });

    test('an absent calibration leaves the barrier off', () {
      final result = Onboarding.combine(
        spanOutcome: const MemorySpanOutcome(span: 4, trialsTaken: 4),
      );
      expect(
        result.forcedGenerationBarrierDefault,
        isFalse,
        reason:
            'guessing overconfidence would switch on a barrier on no evidence',
      );
      expect(result.calibrationVerdict, CalibrationVerdict.insufficient);
    });

    test('a completed calibration is carried through', () {
      const calibration = CalibrationResult(
        verdict: CalibrationVerdict.overconfident,
        meanBias: 0.4,
        sampleSize: 3,
        forcedGenerationBarrierDefault: true,
      );
      final result = Onboarding.combine(
        spanOutcome: const MemorySpanOutcome(span: 5, trialsTaken: 5),
        calibration: calibration,
      );
      expect(result.span, 5);
      expect(result.forcedGenerationBarrierDefault, isTrue);
      expect(result.calibrationVerdict, CalibrationVerdict.overconfident);
    });
  });
}
