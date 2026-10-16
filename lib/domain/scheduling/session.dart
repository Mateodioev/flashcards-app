import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/domain/scheduling/due_queue.dart';

/// One card to show this session, and why it is here.
class SessionItem {
  const new({required this.entry, required this.isNew});

  final DueEntry entry;

  /// True for a card that has never been reviewed.
  final bool isNew;

  int get cardId => entry.cardId;

  @override
  String toString() =>
      'SessionItem(${entry.cardId}, ${isNew ? 'new' : 'review'})';
}

/// A built session: what to show, in order.
class ReviewSession {
  const new({required this.items, required this.newCount});

  final List<SessionItem> items;

  /// How many of [items] are first-time cards.
  final int newCount;

  int get reviewCount => items.length - newCount;

  bool get isEmpty => items.isEmpty;
}

/// What the session builder needs to know about the learner's limits.
class SessionRequest {
  const new({
    required this.now,
    this.courseId,
    this.themeId,
    this.interleaveMode = InterleaveMode.blocked,
    this.newCardsPerDay = 0,
    this.newCardsAlreadyToday = 0,
    this.maxReviewCards = 200,
  });

  final DateTime now;
  final int? courseId;
  final int? themeId;

  /// Applied to the whole session, not just the review portion.
  final InterleaveMode interleaveMode;

  /// The course's per-day intake cap.
  final int newCardsPerDay;

  /// How many new cards were already introduced today.
  ///
  /// Subtracted from [newCardsPerDay], so the cap is genuinely per-day rather
  /// than per-session. Without this, opening the app five times would introduce
  /// five sessions' worth of cards.
  final int newCardsAlreadyToday;

  /// A ceiling on the review portion, so a backlog cannot produce an
  /// endless session.
  final int maxReviewCards;

  /// How many new cards may be introduced now, never negative.
  int get newAllowance {
    final remaining = newCardsPerDay - newCardsAlreadyToday;
    return remaining < 0 ? 0 : remaining;
  }
}

/// Composes reviewed-and-due cards with first-time cards into one session.
///
/// Pure: it receives both lists and orders them. The queries live in the
/// repository, so this is testable without a database.
abstract final class SessionBuilder {
  static ReviewSession build({
    required SessionRequest request,
    required List<DueEntry> due,
    required List<DueEntry> fresh,
  }) {
    final reviewItems = orderDueCards(
      due,
      mode: request.interleaveMode,
      limit: request.maxReviewCards,
    ).map((entry) => SessionItem(entry: entry, isNew: false)).toList();

    // Guard against a card arriving in both populations. It should not happen —
    // a card gains a schedule row precisely when it stops being new — but a
    // duplicate would make the learner review the same card twice in one
    // sitting, so it is filtered rather than trusted.
    final dueIds = reviewItems.map((item) => item.cardId).toSet();

    final allowance = request.newAllowance;
    final newItems = fresh
        .where((entry) => !dueIds.contains(entry.cardId))
        .take(allowance)
        .map((entry) => SessionItem(entry: entry, isNew: true))
        .toList();

    // New cards lead the session. They are the cards most likely to be
    // abandoned if left until the end, and reviewing first would push intake
    // past the point where a learner still has attention for it.
    //
    // Interleaving is applied *within* each portion by `orderDueCards`, not
    // across the boundary: a new card is a different task from a review, and
    // alternating the two would add difficulty without adding the
    // discriminative contrast that interleaving is for.
    final items = <SessionItem>[...newItems, ...reviewItems];

    return ReviewSession(items: items, newCount: newItems.length);
  }
}
