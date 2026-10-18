// Phase 5 of docs/fsrs6_migration_plan.md: regression & compatibility
// verification. Cards already persisted carry FSRS-5 (S, D) values; the
// first FSRS-6 review after the migration must ingest those values and
// advance smoothly — no clamping anomalies, no NaN, no out-of-range state.
//
// Every assertion goes through the domain `Scheduler` with the FSRS-6
// adapter (fuzz off), not through the adapter alone, because the DB rows
// are consumed by that seam in production.

import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/domain/scheduling/fsrs5.dart';
import 'package:flashcards2/domain/scheduling/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reproduces a persisted card whose (S, D) were produced by FSRS-5
/// history: reviews the card through Fsrs5Scheduler and returns the final
/// domain schedule, mirroring what `schedule_states` would store.
CardSchedule historicFsrs5Card(List<Rating> ratings) {
  final fsrs5 = Scheduler(
    SchedulerConfig(memoryEngine: const Fsrs5Scheduler()),
  );
  var card = const CardSchedule.newCard();
  var now = DateTime.utc(2022, 11, 29, 12, 30);
  for (final rating in ratings) {
    final outcome = fsrs5.review(card: card, rating: rating, now: now);
    card = outcome.schedule;
    now = card.due!;
  }
  return card;
}

void main() {
  group('FSRS-5 historical data compatibility (Phase 5)', () {
    final histories = <String, List<Rating>>{
      'fresh after one good': [Rating.good],
      'young graduate': [Rating.good, Rating.good, Rating.good],
      'mature graduate': [
        Rating.good, Rating.good, Rating.good,
        Rating.good, Rating.good, Rating.good, //
      ],
      'post-lapse': [
        Rating.good, Rating.good, Rating.good,
        Rating.good, Rating.good, Rating.good, //
        Rating.again, Rating.again, Rating.good, Rating.good,
      ],
    };

    // A dozen further reviews with mixed ratings, always at the assigned
    // due instant — the realistic first weeks after the migration.
    const followUp = <Rating>[
      Rating.good, Rating.good, Rating.hard, Rating.good, Rating.easy,
      Rating.good, Rating.again, Rating.good, Rating.good, Rating.good,
      Rating.good, Rating.good, //
    ];

    for (final entry in histories.entries) {
      test(
        'card with FSRS-5 state (${entry.key}) advances smoothly under '
        'FSRS-6 without clamping anomalies',
        () {
          final scheduler = Scheduler(); // FSRS-6 adapter, fuzz off
          var card = historicFsrs5Card(entry.value);
          final baselineStability = card.memory!.stability;
          var now = card.due!.add(const Duration(days: 3));

          final intervals = <int>[];
          for (final rating in followUp) {
            final outcome = scheduler.review(
              card: card,
              rating: rating,
              now: now,
            );
            card = outcome.schedule;
            intervals.add(outcome.scheduledDays);

            final memory = card.memory!;
            expect(memory.stability.isNaN, isFalse, reason: 'NaN stability');
            expect(
              memory.stability,
              greaterThanOrEqualTo(0.001),
              reason: 'stability below the FSRS floor',
            );
            expect(
              memory.difficulty,
              inInclusiveRange(1, 10),
              reason: 'difficulty escaped [1, 10]',
            );
            expect(
              outcome.scheduledDays,
              inInclusiveRange(0, 36500),
              reason: 'interval escaped valid bounds',
            );
            now = card.due!;
          }

          // Smooth recovery: the five consecutive goods after the lapse
          // must produce non-decreasing intervals (never stuck at 1).
          final recovery = intervals.sublist(
            followUp.indexOf(Rating.again) + 1,
          );
          for (var i = 1; i < recovery.length; i++) {
            expect(
              recovery[i],
              greaterThanOrEqualTo(recovery[i - 1]),
              reason:
                  'recovery intervals regressed: $recovery '
                  '(history: ${entry.key})',
            );
          }

          // The migrated engine still advances the card: after a dozen
          // follow-up reviews the stability differs from the FSRS-5 one —
          // state is evolving, not frozen by a clamp.
          expect(
            card.memory!.stability,
            isNot(equals(baselineStability)),
            reason: 'stability untouched across the whole follow-up',
          );
        },
      );
    }

    test('post-lapse recovery grows intervals from a small restart', () {
      // The FSRS-6 lapse path is deliberately conservative: the first
      // post-lapse interval is small and then grows geometrically.
      final scheduler = Scheduler();
      var card = historicFsrs5Card(
        List.filled(6, Rating.good),
      );
      var now = card.due!;

      // Lapse the migrated card, then recover with four consecutive goods.
      card = scheduler
          .review(card: card, rating: Rating.again, now: now)
          .schedule;
      now = card.due!;
      final recovery = <int>[];
      for (var i = 0; i < 4; i++) {
        final outcome = scheduler.review(
          card: card,
          rating: Rating.good,
          now: now,
        );
        card = outcome.schedule;
        recovery.add(outcome.scheduledDays);
        now = card.due!;
      }

      expect(recovery.first, lessThanOrEqualTo(recovery.last));
      expect(
        recovery.last,
        greaterThan(recovery.first),
        reason: 'post-lapse recovery must grow intervals: $recovery',
      );
      expect(
        recovery.every((days) => days >= 0 && days <= 36500),
        isTrue,
      );
    });
  });
}
