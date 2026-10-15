import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/domain/scheduling/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

/// Anki-style sub-day learning steps: `1m` then `10m`, relearn `10m`.
///
/// This is the behaviour the app ships, and it is deliberately **not** the
/// configuration that reproduces the canonical interval-history vector — that
/// vector comes from the raw algorithm with a single graduation step. Adding a
/// second step changes the sequence by design, which is exactly why the two are
/// tested separately rather than one being bent to satisfy the other.
void main() {
  const scheduler = Scheduler(
    SchedulerConfig(
      learningSteps: SchedulerConfig.ankiLearning,
      relearningSteps: SchedulerConfig.ankiRelearning,
    ),
  );

  final t0 = DateTime.utc(2022, 11, 29, 12, 30);

  test('a new card walks both learning steps before graduating', () {
    var card = const CardSchedule.newCard();
    var now = t0;

    // Step 1: enters the first step, due in one minute.
    var outcome = scheduler.review(card: card, rating: Rating.good, now: now);
    card = outcome.schedule;
    expect(card.state, ReviewState.learning);
    expect(card.step, 0);
    expect(outcome.scheduledDays, 0);
    expect(card.due, now.add(const Duration(minutes: 1)));

    // Step 2: advances to the ten-minute step, still same-day.
    now = card.due!;
    outcome = scheduler.review(card: card, rating: Rating.good, now: now);
    card = outcome.schedule;
    expect(card.state, ReviewState.learning);
    expect(card.step, 1);
    expect(outcome.scheduledDays, 0);
    expect(card.due, now.add(const Duration(minutes: 10)));

    // Step 3: past the last step, so it graduates to a day-scale interval.
    now = card.due!;
    outcome = scheduler.review(card: card, rating: Rating.good, now: now);
    card = outcome.schedule;
    expect(card.state, ReviewState.review);
    expect(card.step, 0);
    expect(outcome.scheduledDays, greaterThan(0));
  });

  test('Easy graduates immediately from the first step', () {
    final outcome = scheduler.review(
      card: const CardSchedule.newCard(),
      rating: Rating.easy,
      now: t0,
    );
    expect(outcome.schedule.state, ReviewState.review);
    expect(outcome.scheduledDays, greaterThan(0));
  });

  test('Again sends the card back to the first step', () {
    var card = const CardSchedule.newCard();
    var now = t0;
    card = scheduler.review(card: card, rating: Rating.good, now: now).schedule;
    now = card.due!;
    card = scheduler.review(card: card, rating: Rating.good, now: now).schedule;
    expect(card.step, 1);

    now = card.due!;
    card = scheduler
        .review(card: card, rating: Rating.again, now: now)
        .schedule;
    expect(card.state, ReviewState.learning);
    expect(card.step, 0);
  });

  test('Hard repeats the current step without advancing', () {
    var card = const CardSchedule.newCard();
    var now = t0;
    card = scheduler.review(card: card, rating: Rating.good, now: now).schedule;
    now = card.due!;
    card = scheduler.review(card: card, rating: Rating.good, now: now).schedule;
    expect(card.step, 1);

    now = card.due!;
    card = scheduler.review(card: card, rating: Rating.hard, now: now).schedule;
    expect(card.state, ReviewState.learning);
    expect(card.step, 1, reason: 'Hard must not advance the step index');
  });

  test('a graduated card lapses into the relearning steps', () {
    var card = const CardSchedule.newCard();
    var now = t0;
    for (var i = 0; i < 3; i++) {
      card = scheduler
          .review(card: card, rating: Rating.good, now: now)
          .schedule;
      now = card.due!;
    }
    expect(card.state, ReviewState.review);
    expect(card.lapses, 0);

    final lapsed = scheduler.review(card: card, rating: Rating.again, now: now);
    expect(lapsed.schedule.state, ReviewState.relearning);
    expect(lapsed.schedule.lapses, 1);
    expect(lapsed.scheduledDays, 0);

    // Relearning walks its own steps, then returns to review.
    var relearn = lapsed.schedule;
    final when = relearn.due!;
    relearn = scheduler
        .review(card: relearn, rating: Rating.good, now: when)
        .schedule;
    expect(relearn.state, ReviewState.review);
    expect(relearn.lapses, 1, reason: 'lapse count must not reset on recovery');
  });

  test('step index is clamped so a stale value cannot overflow the list', () {
    // A card persisted with step 5 while only two steps exist must not throw.
    final card = CardSchedule(state: ReviewState.learning, step: 5, due: t0);
    final outcome = scheduler.review(card: card, rating: Rating.hard, now: t0);
    expect(outcome.schedule.step, lessThan(2));
  });
}
