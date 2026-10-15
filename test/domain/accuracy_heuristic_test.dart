import 'package:flashcards2/domain/entities/scheduling.dart';
import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/domain/scheduling/accuracy_heuristic.dart';
import 'package:flutter_test/flutter_test.dart';

ReviewLog log(Rating rating) {
  return ReviewLog(
    id: 0,
    cardId: 1,
    rating: rating,
    reviewedAt: DateTime(2022, 12),
    elapsedDays: 1,
    scheduledDays: 1,
    state: ReviewState.review,
    durationMs: 1000,
    hintUsed: false,
    barrierCompleted: true,
  );
}

List<ReviewLog> logs({required int again, required int good}) {
  return <ReviewLog>[
    for (var i = 0; i < good; i++) log(Rating.good),
    for (var i = 0; i < again; i++) log(Rating.again),
  ];
}

void main() {
  const heuristic = AccuracyHeuristic();

  test('reports insufficient below the minimum sample', () {
    final advice = heuristic.advise(logs(again: 1, good: 5));
    expect(advice.band, AccuracyBand.insufficient);
    expect(advice.sampleSize, 6);
    expect(advice.accuracy, isNull);
    expect(advice.newCardFactor, 1, reason: 'no advice means no change');
  });

  test('widen when accuracy is at or above the upper band', () {
    final advice = heuristic.advise(logs(again: 0, good: 20));
    expect(advice.band, AccuracyBand.widen);
    expect(advice.accuracy, 1.0);
    expect(advice.newCardFactor, 1);
  });

  test('hold inside the target window', () {
    // 17/20 = 0.85, between 0.75 and 0.95.
    final advice = heuristic.advise(logs(again: 3, good: 17));
    expect(advice.band, AccuracyBand.hold);
    expect(advice.accuracy, closeTo(0.85, 1e-9));
    expect(advice.newCardFactor, 1);
  });

  test('tighten below the lower band and reduce intake', () {
    // 10/20 = 0.5.
    final advice = heuristic.advise(logs(again: 10, good: 10));
    expect(advice.band, AccuracyBand.tighten);
    expect(advice.accuracy, closeTo(0.5, 1e-9));
    expect(
      advice.newCardFactor,
      lessThan(1),
      reason: 'tighten must actually reduce new-card intake',
    );
  });

  test('only Again counts as a miss', () {
    expect(AccuracyHeuristic.isCorrect(Rating.good), isTrue);
    expect(AccuracyHeuristic.isCorrect(Rating.easy), isTrue);
    expect(
      AccuracyHeuristic.isCorrect(Rating.hard),
      isTrue,
      reason: 'hard is a successful recall, not a failure',
    );
    expect(AccuracyHeuristic.isCorrect(Rating.again), isFalse);
  });

  test('band boundaries are inclusive at both edges', () {
    // Exactly 0.95 -> widen.
    expect(heuristic.advise(logs(again: 1, good: 19)).band, AccuracyBand.widen);
    // Exactly 0.75 -> tighten (not hold).
    expect(
      heuristic.advise(logs(again: 5, good: 15)).band,
      AccuracyBand.tighten,
    );
  });

  test('only the most recent window is considered', () {
    // 5 recent misses with 40 older successes: the recent window must dominate.
    final mixed = <ReviewLog>[
      for (var i = 0; i < 5; i++) log(Rating.again),
      for (var i = 0; i < 40; i++) log(Rating.good),
    ];
    const narrow = AccuracyHeuristic(window: 10, minimumSample: 5);
    final advice = narrow.advise(mixed);
    expect(advice.sampleSize, 10);
    expect(
      advice.band,
      AccuracyBand.tighten,
      reason: 'stale history must not mask a recent decline',
    );
  });

  test('every band carries a non-empty explanation', () {
    final bands = <AccuracyAdvice>[
      heuristic.advise(logs(again: 0, good: 5)),
      heuristic.advise(logs(again: 0, good: 20)),
      heuristic.advise(logs(again: 3, good: 17)),
      heuristic.advise(logs(again: 10, good: 10)),
    ];
    for (final advice in bands) {
      expect(advice.explanation, isNotEmpty);
    }
  });
}
