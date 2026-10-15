import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/domain/scheduling/due_queue.dart';
import 'package:flashcards2/domain/scheduling/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

DueEntry entry(int cardId, int themeId, {int courseId = 1, int day = 1}) {
  return DueEntry(
    cardId: cardId,
    themeId: themeId,
    courseId: courseId,
    due: DateTime.utc(2022, 12, day),
  );
}

void main() {
  group('orderDueCards', () {
    test('blocked keeps each theme contiguous, due order within a theme', () {
      final due = <DueEntry>[
        entry(1, 1, day: 3),
        entry(2, 2),
        entry(3, 1),
        entry(4, 2, day: 2),
      ];

      final ordered = orderDueCards(due, mode: InterleaveMode.blocked);

      expect(
        ordered.map((e) => e.cardId).toList(),
        <int>[3, 1, 2, 4],
        reason: 'theme 1 first (3 before 1 by due), then theme 2 (2 before 4)',
      );
    });

    test('interleaved round-robins across themes', () {
      final due = <DueEntry>[
        entry(1, 1),
        entry(2, 1, day: 2),
        entry(3, 1, day: 3),
        entry(4, 2),
        entry(5, 2, day: 2),
      ];

      final ordered = orderDueCards(due, mode: InterleaveMode.interleaved);

      expect(ordered.map((e) => e.cardId).toList(), <int>[
        1,
        4,
        2,
        5,
        3,
      ], reason: 'alternates themes, then continues with the longer theme');
    });

    test('interleaving produces adjacent cards from different themes', () {
      final due = <DueEntry>[
        for (var i = 1; i <= 4; i++) entry(i, 1),
        for (var i = 5; i <= 8; i++) entry(i, 2),
      ];

      final ordered = orderDueCards(due, mode: InterleaveMode.interleaved);

      for (var i = 1; i < ordered.length; i++) {
        expect(
          ordered[i].themeId,
          isNot(ordered[i - 1].themeId),
          reason: 'the contrast between neighbouring themes is the mechanism',
        );
      }
    });

    test('ordering is deterministic across repeated calls', () {
      final due = <DueEntry>[entry(3, 2, day: 2), entry(1, 1), entry(2, 2)];
      final first = orderDueCards(due, mode: InterleaveMode.interleaved);
      final second = orderDueCards(due, mode: InterleaveMode.interleaved);
      expect(first.map((e) => e.cardId), second.map((e) => e.cardId));
    });

    test('limit truncates the ordered queue, not the input', () {
      final due = <DueEntry>[
        entry(1, 1, day: 3),
        entry(2, 1),
        entry(3, 1, day: 2),
      ];
      final ordered = orderDueCards(
        due,
        mode: InterleaveMode.blocked,
        limit: 2,
      );
      expect(ordered.map((e) => e.cardId).toList(), <int>[2, 3]);
    });

    test('an empty queue is not an error, and no mode throws', () {
      for (final mode in InterleaveMode.values) {
        expect(orderDueCards(<DueEntry>[], mode: mode), isEmpty);
      }
    });
  });

  group('day cutoff (T3.5)', () {
    test('the cutoff shifts which day a review belongs to', () {
      // 2am with a 4am cutoff is still "yesterday".
      final lateNight = DateTime(2022, 12, 2, 2);
      final previousEvening = DateTime(2022, 12, 1, 22);
      final dayIndex = Scheduler.dayIndex(lateNight);
      expect(
        dayIndex,
        Scheduler.dayIndex(previousEvening),
        reason: 'both instants fall in the same shifted calendar day',
      );
    });

    test('a midnight cutoff makes the calendar day authoritative', () {
      final lateNight = DateTime(2022, 12, 2, 2);
      final previousEvening = DateTime(2022, 12, 1, 22);
      expect(
        Scheduler.dayIndex(lateNight, 0),
        isNot(Scheduler.dayIndex(previousEvening, 0)),
      );
    });

    test('elapsedDays counts shifted days, not 24-hour blocks', () {
      final start = DateTime(2022, 12, 1, 22);
      final end = DateTime(2022, 12, 2, 2);
      // Four hours apart, but with a 4am cutoff these are the same day.
      expect(Scheduler.elapsedDays(start, end), 0);
      expect(Scheduler.elapsedDays(start, end, cutoffHour: 0), 1);
    });

    test('elapsedDays never goes negative when time runs backwards', () {
      final later = DateTime(2022, 12, 3);
      final earlier = DateTime(2022, 12);
      expect(Scheduler.elapsedDays(later, earlier), 0);
    });

    test('whole-day intervals are unaffected by the cutoff', () {
      // The canonical vectors must not depend on this setting.
      final start = DateTime(2022, 12, 1, 12);
      final end = DateTime(2022, 12, 5, 12);
      for (final cutoff in <int>[0, 4, 12, 23]) {
        expect(
          Scheduler.elapsedDays(start, end, cutoffHour: cutoff),
          4,
          reason: 'cutoff $cutoff must not change a whole-day gap',
        );
      }
    });

    test('a cutoff does not change the canonical interval history', () {
      const withCutoff = Scheduler();
      const expected = <int>[0, 4, 14, 44, 125, 328, 0, 0, 6, 14, 31, 65, 130];
      const ratings = <Rating>[
        Rating.good,
        Rating.good,
        Rating.good,
        Rating.good,
        Rating.good,
        Rating.good,
        Rating.again,
        Rating.again,
        Rating.good,
        Rating.good,
        Rating.good,
        Rating.good,
        Rating.good,
      ];

      var card = const CardSchedule.newCard();
      var now = DateTime.utc(2022, 11, 29, 12, 30);
      final actual = <int>[];
      for (final rating in ratings) {
        final outcome = withCutoff.review(card: card, rating: rating, now: now);
        card = outcome.schedule;
        actual.add(outcome.scheduledDays);
        now = card.due!;
      }
      expect(actual, expected);
    });
  });
}
