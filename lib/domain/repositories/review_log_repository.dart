import 'package:flashcards2/domain/entities/scheduling.dart';

/// Persistence boundary for the append-only review log.
///
/// There is intentionally no `update` or `delete`: the history is immutable.
/// A correction is a new row, never an edit.
abstract interface class ReviewLogRepository {
  Future<ReviewLog> append(ReviewLog log);

  Future<List<ReviewLog>> findByCard(int cardId, {int? limit});

  Future<List<ReviewLog>> findAll();
}
