import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/domain/scheduling/due_queue.dart';
import 'package:flashcards2/domain/scheduling/global_session.dart';
import 'package:flutter_test/flutter_test.dart';

DueEntry entry(int cardId, {int themeId = 1, int courseId = 1, int day = 1}) {
  return DueEntry(
    cardId: cardId,
    themeId: themeId,
    courseId: courseId,
    due: DateTime.utc(2022, 12, day),
  );
}

CourseStudyPolicy policy(
  int courseId, {
  InterleaveMode mode = InterleaveMode.blocked,
  int perDay = 10,
  int already = 0,
}) {
  return CourseStudyPolicy(
    courseId: courseId,
    interleaveMode: mode,
    newCardsPerDay: perDay,
    newCardsAlreadyToday: already,
  );
}

void main() {
  group('GlobalSessionBuilder', () {
    test('reviews lead and new cards follow', () {
      final session = GlobalSessionBuilder.build(
        request: GlobalSessionRequest(policies: [policy(1)]),
        due: [entry(1)],
        fresh: [entry(2)],
      );
      expect(session.items.map((i) => i.cardId).toList(), [1, 2]);
      expect(session.newCount, 1);
      expect(session.reviewCount, 1);
    });

    test('course blocks stay contiguous in ascending course order', () {
      final session = GlobalSessionBuilder.build(
        request: GlobalSessionRequest(policies: [policy(1), policy(2)]),
        due: [entry(20, courseId: 2), entry(10, day: 2)],
        fresh: [],
      );
      // Course 1's block leads even though course 2 is due earlier.
      expect(session.items.map((i) => i.cardId).toList(), [10, 20]);
    });

    test('each course applies its own interleave mode inside its block', () {
      final session = GlobalSessionBuilder.build(
        request: GlobalSessionRequest(
          policies: [policy(1, mode: InterleaveMode.interleaved)],
        ),
        due: [entry(1), entry(2, themeId: 2), entry(3, day: 2)],
        fresh: [],
      );
      expect(session.items.map((i) => i.cardId).toList(), [1, 2, 3]);
    });

    test('per-course allowance limits new intake', () {
      final session = GlobalSessionBuilder.build(
        request: GlobalSessionRequest(
          policies: [policy(1, perDay: 1), policy(2, perDay: 1)],
        ),
        due: [],
        fresh: [entry(1), entry(2), entry(3, courseId: 2)],
      );
      expect(session.newCount, 2);
      expect(session.items.map((i) => i.cardId).toList(), [
        1,
        3,
      ], reason: 'one new card from each course');
    });

    test('the global ceiling caps new intake across all courses', () {
      final session = GlobalSessionBuilder.build(
        request: GlobalSessionRequest(
          policies: [policy(1), policy(2)],
          globalNewCardCeiling: 3,
        ),
        due: [],
        fresh: [
          entry(1),
          entry(2),
          entry(3),
          entry(4, courseId: 2),
          entry(5, courseId: 2),
        ],
      );
      expect(session.newCount, 3);
      expect(session.items.map((i) => i.cardId).toList(), [1, 2, 3]);
    });

    test('the review ceiling bounds a large backlog', () {
      final session = GlobalSessionBuilder.build(
        request: GlobalSessionRequest(policies: [policy(1)], maxReviewCards: 2),
        due: [entry(1), entry(2), entry(3)],
        fresh: [],
      );
      expect(session.reviewCount, 2);
    });

    test('a card in both populations is shown once, as a review', () {
      final session = GlobalSessionBuilder.build(
        request: GlobalSessionRequest(policies: [policy(1)]),
        due: [entry(1)],
        fresh: [entry(1)],
      );
      expect(session.items.map((i) => i.cardId).toList(), [1]);
      expect(session.newCount, 0);
    });

    test('a due+fresh card beyond the review cap is not re-introduced', () {
      final session = GlobalSessionBuilder.build(
        request: GlobalSessionRequest(policies: [policy(1)], maxReviewCards: 1),
        due: [entry(1), entry(2)],
        fresh: [entry(2)],
      );
      expect(session.items.map((i) => i.cardId).toList(), [1]);
      expect(session.newCount, 0);
    });
  });
}
