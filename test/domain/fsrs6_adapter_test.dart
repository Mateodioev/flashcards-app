// Acceptance tests for the FSRS-6 anti-corruption layer.
//
// The canonical interval vector is derived from the FSRS-6 default
// 21-parameter weights — the same vector package:fsrs 2.0.1 reproduces
// (verified in the Phase 1 spike, docs/fsrs6_migration_plan.md). Phase 4
// re-derives it from fsrs-rs/py-fsrs with repo+commit provenance and moves
// it into test/domain/fsrs6_reference_vectors_test.dart; this file pins the
// ADAPTER contract (mappings, granularity, determinism, Option A semantics).
//
// Determinism: every harness here constructs the adapter with
// `enableFuzzing: false` (package fuzzing is ON by default — see the
// migration plan, Phase 1 step 5 and Phase 2 decision 5).

import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/domain/scheduling/fsrs5.dart';
import 'package:flashcards2/domain/scheduling/fsrs6_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Fsrs6SchedulerAdapter', () {
    test('reproduces the canonical FSRS-6 interval vector '
        '[G x6, A x2, G x5] -> [0,4,14,45,135,372,0,0,2,5,10,20,40] '
        'under the domain step semantics', () {
      final adapter = Fsrs6SchedulerAdapter(enableFuzzing: false);

      const ratings = [
        Rating.good, Rating.good, Rating.good, Rating.good, Rating.good,
        Rating.good, //
        Rating.again, Rating.again, //
        Rating.good, Rating.good, Rating.good, Rating.good, Rating.good,
      ];
      const expected = [0, 4, 14, 45, 135, 372, 0, 0, 2, 5, 10, 20, 40];

      // Mirror the domain Scheduler's step semantics (single 1m learning
      // step, single 10m relearning step): a review that enters a sub-day
      // step schedules 0 whole days and never calls nextInterval; a
      // graduating review calls nextInterval on the produced memory state.
      var state = ReviewState.new_;
      MemoryState? memory;
      var day = 0;
      var lastDay = 0;
      final intervals = <int>[];
      for (final rating in ratings) {
        memory = adapter.nextMemoryState(
          current: memory,
          elapsedDays: (day - lastDay).toDouble(),
          rating: rating,
        );
        lastDay = day;

        final interval = switch (state) {
          ReviewState.new_ => 0, // enters the learning step
          ReviewState.learning => adapter.nextInterval(memory.stability),
          ReviewState.review => rating == Rating.again
              ? 0 // enters the relearning step
              : adapter.nextInterval(memory.stability),
          ReviewState.relearning => rating == Rating.again
              ? 0 // resets the relearning step
              : adapter.nextInterval(memory.stability),
        };
        intervals.add(interval);
        day += interval;

        state = switch (state) {
          ReviewState.new_ => ReviewState.learning,
          ReviewState.learning => ReviewState.review,
          ReviewState.review => rating == Rating.again
              ? ReviewState.relearning
              : ReviewState.review,
          ReviewState.relearning => rating == Rating.again
              ? ReviewState.relearning
              : ReviewState.review,
        };
      }

      expect(intervals, expected);
    });

    test('is deterministic with fuzzing disabled across instances', () {
      MemoryState? a;
      MemoryState? b;
      final first = Fsrs6SchedulerAdapter(enableFuzzing: false);
      final second = Fsrs6SchedulerAdapter(enableFuzzing: false);
      for (var i = 0; i < 6; i++) {
        a = first.nextMemoryState(
          current: a,
          elapsedDays: i.isEven ? 0 : 4,
          rating: Rating.good,
        );
        b = second.nextMemoryState(
          current: b,
          elapsedDays: i.isEven ? 0 : 4,
          rating: Rating.good,
        );
      }
      expect(a!.stability, b!.stability);
      expect(a.difficulty, b.difficulty);
      expect(first.nextInterval(a.stability), second.nextInterval(b.stability));
    });

    test('first review initializes from the rating (initial S/D)', () {
      final adapter = Fsrs6SchedulerAdapter(enableFuzzing: false);
      final good = adapter.nextMemoryState(
        rating: Rating.good,
      );
      final again = adapter.nextMemoryState(
        rating: Rating.again,
      );

      // package:fsrs 2.0.1 defaults: w0=0.2172 (again), w2=3.2602 (good).
      expect(good.stability, greaterThan(again.stability));
      expect(good.difficulty, lessThan(again.difficulty));
    });

    test('Option A: a same-day review applies the w19 short-term formula '
        'without shrinking for good', () {
      final adapter = Fsrs6SchedulerAdapter(enableFuzzing: false);
      final initial = adapter.nextMemoryState(
        rating: Rating.good,
      );
      final sameDay = adapter.nextMemoryState(
        current: initial,
        rating: Rating.good,
      );

      // w19 same-day: stability increases for a same-day good recall.
      expect(sameDay.stability, greaterThan(initial.stability));
    });

    test('accepted package behavior: a same-day hard may decrease stability '
        '(docs/fsrs6_migration_plan.md, Phase 2 decision 4)', () {
      final adapter = Fsrs6SchedulerAdapter(enableFuzzing: false);
      final initial = adapter.nextMemoryState(
        rating: Rating.good,
      );
      final afterHard = adapter.nextMemoryState(
        current: initial,
        rating: Rating.hard,
      );

      // package:fsrs 2.0.1 clamps the same-day increase to >= 1 only for
      // good/easy; hard diverges from py-fsrs/fsrs-rs by design acceptance.
      expect(afterHard.stability, lessThan(initial.stability));
    });

    test('elapsed days route through the forgetting curve '
        '(long-term review differs from same-day review)', () {
      final adapter = Fsrs6SchedulerAdapter(enableFuzzing: false);
      final initial = adapter.nextMemoryState(
        rating: Rating.good,
      );
      final sameDay = adapter.nextMemoryState(
        current: initial,
        rating: Rating.good,
      );
      final afterDays = adapter.nextMemoryState(
        current: initial,
        elapsedDays: 4,
        rating: Rating.good,
      );

      expect(sameDay.stability, isNot(equals(afterDays.stability)));
      // A recall 4 days later still grows stability for a young card.
      expect(afterDays.stability, greaterThan(initial.stability));
    });

    test('maps the four domain ratings', () {
      final adapter = Fsrs6SchedulerAdapter(enableFuzzing: false);
      for (final rating in Rating.values) {
        final memory = adapter.nextMemoryState(
          rating: rating,
        );
        expect(memory.stability, greaterThan(0));
        expect(memory.difficulty, inInclusiveRange(1, 10));
      }
    });

    test('nextInterval clamps to [1, 36500] whole days', () {
      final adapter = Fsrs6SchedulerAdapter(enableFuzzing: false);
      expect(adapter.nextInterval(0), 1);
      expect(adapter.nextInterval(1000000000), 36500);
    });

    test('paired and unpaired nextInterval agree with fuzzing disabled', () {
      final adapter = Fsrs6SchedulerAdapter(enableFuzzing: false);
      var memory = adapter.nextMemoryState(
        rating: Rating.good,
      );
      for (var day = 4; day <= 20; day += 8) {
        memory = adapter.nextMemoryState(
          current: memory,
          elapsedDays: day.toDouble(),
          rating: Rating.good,
        );
      }
      final paired = adapter.nextInterval(memory.stability);

      final fresh = Fsrs6SchedulerAdapter(enableFuzzing: false);
      expect(fresh.nextInterval(memory.stability), paired);
    });
  });
}
