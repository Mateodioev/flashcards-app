import 'package:drift/drift.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/data/tables/tables.dart';

part 'review_log_dao.g.dart';

/// Append-only access to the review log.
///
/// There is deliberately no update or delete method. The log is the historical
/// input a future FSRS weight-optimization pass may read, so mutating it would
/// silently corrupt that input.
@DriftAccessor(tables: [ReviewLogs])
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
}
