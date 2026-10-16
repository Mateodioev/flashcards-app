import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/domain/scheduling/due_queue.dart';
import 'package:flashcards2/domain/scheduling/session.dart';
import 'package:flutter_test/flutter_test.dart';

DueEntry entry(int cardId, {int themeId = 1, int day = 1}) {
  return DueEntry(
    cardId: cardId,
    themeId: themeId,
    courseId: 1,
    due: DateTime.utc(2022, 12, day),
  );
}

SessionRequest request({
  InterleaveMode mode = InterleaveMode.blocked,
  int newCardsPerDay = 10,
  int newCardsAlreadyToday = 0,
  int maxReviewCards = 200,
}) {
  return SessionRequest(
    now: DateTime.utc(2022, 12, 10),
    interleaveMode: mode,
    newCardsPerDay: newCardsPerDay,
    newCardsAlreadyToday: newCardsAlreadyToday,
    maxReviewCards: maxReviewCards,
  );
}

void main() {
  group('SessionBuilder', () {
    test('an empty database yields an empty session, not an error', () {
      final session = SessionBuilder.build(
        request: request(),
        due: <DueEntry>[],
        fresh: <DueEntry>[],
      );
      expect(session.isEmpty, isTrue);
      expect(session.newCount, 0);
      expect(session.reviewCount, 0);
    });

    test('new cards alone produce a session', () {
      // The case that was previously impossible: a brand-new theme has no
      // schedule rows at all, so only `fresh` can populate a session.
      final session = SessionBuilder.build(
        request: request(),
        due: <DueEntry>[],
        fresh: <DueEntry>[entry(1), entry(2)],
      );
      expect(session.items, hasLength(2));
      expect(session.newCount, 2);
      expect(session.items.every((i) => i.isNew), isTrue);
    });

    test('due cards alone produce a session with no new cards', () {
      final session = SessionBuilder.build(
        request: request(),
        due: <DueEntry>[entry(1), entry(2)],
        fresh: <DueEntry>[],
      );
      expect(session.reviewCount, 2);
      expect(session.newCount, 0);
    });

    test('new cards lead the session', () {
      final session = SessionBuilder.build(
        request: request(),
        due: <DueEntry>[entry(9)],
        fresh: <DueEntry>[entry(1)],
      );
      expect(session.items.first.isNew, isTrue);
      expect(session.items.last.isNew, isFalse);
    });

    test('the new-card cap is respected', () {
      final session = SessionBuilder.build(
        request: request(newCardsPerDay: 3),
        due: <DueEntry>[],
        fresh: <DueEntry>[entry(1), entry(2), entry(3), entry(4), entry(5)],
      );
      expect(session.newCount, 3);
    });

    test('cards already introduced today reduce the allowance', () {
      final session = SessionBuilder.build(
        request: request(newCardsPerDay: 5, newCardsAlreadyToday: 4),
        due: <DueEntry>[],
        fresh: <DueEntry>[entry(1), entry(2), entry(3)],
      );
      expect(
        session.newCount,
        1,
        reason: 'the cap is per day, not per session',
      );
    });

    test('an exhausted allowance admits no new cards but keeps reviews', () {
      final session = SessionBuilder.build(
        request: request(newCardsPerDay: 2, newCardsAlreadyToday: 2),
        due: <DueEntry>[entry(7)],
        fresh: <DueEntry>[entry(1)],
      );
      expect(session.newCount, 0);
      expect(session.reviewCount, 1);
    });

    test('an over-counted day cannot produce a negative allowance', () {
      final session = SessionBuilder.build(
        request: request(newCardsPerDay: 2, newCardsAlreadyToday: 99),
        due: <DueEntry>[],
        fresh: <DueEntry>[entry(1)],
      );
      expect(session.newCount, 0);
      expect(session.isEmpty, isTrue);
    });

    test('the review ceiling bounds a large backlog', () {
      final session = SessionBuilder.build(
        request: request(maxReviewCards: 2),
        due: <DueEntry>[for (var i = 1; i <= 10; i++) entry(i)],
        fresh: <DueEntry>[],
      );
      expect(session.reviewCount, 2);
    });

    test('interleaving applies within the review portion', () {
      final session = SessionBuilder.build(
        request: request(mode: InterleaveMode.interleaved),
        due: <DueEntry>[entry(1), entry(2), entry(3, themeId: 2)],
        fresh: <DueEntry>[],
      );
      final ids = session.items.map((i) => i.cardId).toList();
      expect(ids, <int>[1, 3, 2], reason: 'round-robins across themes');
    });

    test('blocked mode keeps themes together', () {
      final session = SessionBuilder.build(
        request: request(),
        due: <DueEntry>[entry(1, themeId: 2), entry(2), entry(3)],
        fresh: <DueEntry>[],
      );
      final ids = session.items.map((i) => i.cardId).toList();
      expect(ids, <int>[2, 3, 1], reason: 'theme 1 before theme 2');
    });

    test('build is deterministic across repeated calls', () {
      final due = <DueEntry>[entry(2, themeId: 2), entry(1)];
      final fresh = <DueEntry>[entry(5)];
      final first = SessionBuilder.build(
        request: request(mode: InterleaveMode.interleaved),
        due: due,
        fresh: fresh,
      );
      final second = SessionBuilder.build(
        request: request(mode: InterleaveMode.interleaved),
        due: due,
        fresh: fresh,
      );
      expect(
        first.items.map((i) => i.cardId),
        second.items.map((i) => i.cardId),
      );
    });

    test('a card in both lists is shown only once', () {
      // Should not happen — a card gains a schedule row precisely when it stops
      // being new — but a duplicate would make the learner review the same card
      // twice in one sitting, so the builder filters rather than trusts.
      final session = SessionBuilder.build(
        request: request(),
        due: <DueEntry>[entry(1)],
        fresh: <DueEntry>[entry(1)],
      );
      final ids = session.items.map((i) => i.cardId).toList();
      expect(ids.where((id) => id == 1), hasLength(1));
      expect(session.newCount, 0, reason: 'the due entry wins');
    });
  });
}
