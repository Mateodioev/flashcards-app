import 'package:flashcards2/domain/entities/scheduling.dart';

/// Persistence boundary for the append-only review log.
///
/// There is intentionally no `update` or `delete`: the history is immutable.
/// A correction is a new row, never an edit.
abstract interface class ReviewLogRepository {
  Future<ReviewLog> append(ReviewLog log);

  Future<List<ReviewLog>> findByCard(int cardId, {int? limit});

  Future<List<ReviewLog>> findAll();

  /// The most recent reviews, newest first, optionally scoped to one course.
  ///
  /// Feeds the accuracy heuristic, which reads history rather than a running
  /// counter.
  Future<List<ReviewLog>> recent({int? courseId, int limit = 50});
}
