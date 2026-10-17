import 'package:drift/drift.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/data/tables/tables.dart';

part 'review_log_dao.g.dart';

/// Append-only access to the review log.
///
/// There is deliberately no update or delete method. The log is the historical
/// input a future FSRS weight-optimization pass may read, so mutating it would
/// silently corrupt that input.
@DriftAccessor(tables: [ReviewLogs, Cards, Themes])
class ReviewLogDao extends DatabaseAccessor<AppDatabase>
    with _$ReviewLogDaoMixin {
  new(super.attachedDatabase);

  Future<ReviewLogRow> append(ReviewLogsCompanion log) {
    return into(reviewLogs).insertReturning(log);
  }

  Future<List<ReviewLogRow>> byCard(int cardId, {int? limit}) {
    final query = select(reviewLogs)
      ..where((t) => t.cardId.equals(cardId))
      ..orderBy([(t) => OrderingTerm.desc(t.reviewedAt)]);
    if (limit != null) {
      query.limit(limit);
    }
    return query.get();
  }

  Future<List<ReviewLogRow>> all() => select(reviewLogs).get();

  /// Most recent reviews first, optionally limited to one course's cards.
  ///
  /// The course filter resolves through two hops — theme, then card — as nested
  /// `IN` subqueries, so it stays a single statement rather than loading card
  /// ids into Dart first.
  Future<List<ReviewLogRow>> recent({int? courseId, int limit = 50}) {
    final query = select(reviewLogs);

    if (courseId != null) {
      final themeIds = selectOnly(themes)
        ..addColumns([themes.id])
        ..where(themes.courseId.equals(courseId));

      final cardIds = selectOnly(cards)
        ..addColumns([cards.id])
        ..where(cards.themeId.isInQuery(themeIds));

      query.where((_) => reviewLogs.cardId.isInQuery(cardIds));
    }

    query
      ..orderBy([(t) => OrderingTerm.desc(t.reviewedAt)])
      ..limit(limit);
    return query.get();
  }

  /// The earliest review instant for every card, optionally scoped to one
  /// course or theme.
  ///
  /// One row per card, so the repository can decide — with the day cutoff it
  /// receives — which of these instants fall on "today". A card's *first*
  /// review is when it was introduced, so this is the intake ledger rather than
  /// a simple review count.
  Future<List<DateTime>> firstReviewDates({int? courseId, int? themeId}) {
    final firstReview = reviewLogs.reviewedAt.min();
    final query = selectOnly(reviewLogs)
      ..addColumns([firstReview])
      ..join([
        innerJoin(cards, cards.id.equalsExp(reviewLogs.cardId)),
        innerJoin(themes, themes.id.equalsExp(cards.themeId)),
      ]);

    if (courseId != null) {
      query.where(themes.courseId.equals(courseId));
    }
    if (themeId != null) {
      query.where(cards.themeId.equals(themeId));
    }

    query.groupBy([reviewLogs.cardId]);

    return query.get().then(
      (rows) => rows
          .map((row) => row.read(firstReview))
          .whereType<DateTime>()
          .toList(),
    );
  }
}
