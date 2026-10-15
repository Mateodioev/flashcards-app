import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/domain/scheduling/fsrs5.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reference vectors from the canonical FSRS-5 implementation.
///
/// Source: `docs/design.md` -> "Scheduler: FSRS-5 (verified)" -> "Reference
/// vectors". These are the acceptance gate for the port. If one fails, the
/// port is wrong and the tolerance must NOT be loosened to force it green.
void main() {
  const scheduler = Fsrs5Scheduler();
  const shortTermOff = Fsrs5Scheduler(enableShortTerm: false);

  group('constants', () {
    test('factor is derived from decay, not hardcoded', () {
      // exp((1 / -0.5) * ln 0.9) - 1 == 19/81.
      expect(Fsrs5.factor, closeTo(19 / 81, 1e-12));
      expect(Fsrs5.factor, closeTo(0.2345679012345679, 1e-12));
    });

    test('weight vector is FSRS-5 shaped (19 entries, no w19)', () {
      expect(Fsrs5.defaultWeights.length, 19);
    });

    test('short-term saturation exponent is the fixed 0.01 floor', () {
      // Not a weight-vector entry: FSRS-5 has no w19 slot. Established
      // empirically against the memory-state vector below — omitting this
      // factor misses by 5.7e-3, and using the FSRS-6 default w19 (0.0658)
      // misses by 3.2e-2.
      expect(Fsrs5.shortTermSaturation, 0.01);
    });

    test('interval modifier is 1.0 at the default retention', () {
      // R(S, S) == 0.9 by construction, so an interval equal to stability
      // must be exactly one stability unit at retention 0.9.
      expect(scheduler.intervalModifier, closeTo(1.0, 1e-12));
    });

    test('retrievability equals 0.9 when elapsed equals stability', () {
      expect(scheduler.retrievability(10, 10), closeTo(0.9, 1e-12));
    });
  });

  group('first review of a new card', () {
    // Index order is Rating.values: again, hard, good, easy.
    const expectedStability = <double>[0.40255, 1.18385, 3.173, 15.69105];
    const expectedDifficulty = <double>[
      7.1949,
      6.48830527,
      5.28243442,
      3.22450159,
    ];

    test('stability matches S0(G) = w[G-1]', () {
      for (final rating in Rating.values) {
        final state = scheduler.nextMemoryState(
          current: null,
          elapsedDays: 0,
          rating: rating,
        );
        expect(
          state.stability,
          closeTo(expectedStability[rating.index], 1e-4),
          reason: 'stability mismatch for $rating',
        );
      }
    });

    test('difficulty matches D0(G)', () {
      for (final rating in Rating.values) {
        final state = scheduler.nextMemoryState(
          current: null,
          elapsedDays: 0,
          rating: rating,
        );
        expect(
          state.difficulty,
          closeTo(expectedDifficulty[rating.index], 1e-4),
          reason: 'difficulty mismatch for $rating',
        );
      }
    });
  });

  group('memory state after [Again, Good x5]', () {
    const ratings = <Rating>[
      Rating.again,
      Rating.good,
      Rating.good,
      Rating.good,
      Rating.good,
      Rating.good,
    ];
    // Days elapsed before each review, applied cumulatively upstream.
    const elapsed = <double>[0, 0, 1, 3, 8, 21];

    MemoryState run(Fsrs5Scheduler s) {
      MemoryState? state;
      for (var i = 0; i < ratings.length; i++) {
        state = s.nextMemoryState(
          current: state,
          elapsedDays: elapsed[i],
          rating: ratings[i],
        );
      }
      return state!;
    }

    test('short-term enabled matches the reference vector', () {
      final state = run(scheduler);
      expect(state.stability, closeTo(48.27115294, 1e-4));
      expect(state.difficulty, closeTo(7.10441712, 1e-4));
    });

    test('short-term disabled matches the reference vector', () {
      final state = run(shortTermOff);
      expect(state.stability, closeTo(48.065163, 1e-4));
      expect(state.difficulty, closeTo(7.10441712, 1e-4));
    });

    test('the two branches genuinely differ', () {
      expect(
        run(scheduler).stability,
        isNot(closeTo(run(shortTermOff).stability, 1e-6)),
      );
    });
  });
}
