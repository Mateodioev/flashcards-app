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

  /// How many cards were introduced (received their first review) during the
  /// scheduling day that contains [now], in one course or across all courses.
  ///
  /// The new-card cap lives on the course, so the count is course-scoped rather
  /// than theme-scoped: cards introduced in *any* of a course's themes count
  /// against that course's daily allowance.
  ///
  /// [dayCutoffHour] shifts the day boundary the same way the scheduler does,
  /// so a 2am review counts as part of the previous day under a 4am cutoff.
  Future<int> countNewCardsIntroducedToday({
    required DateTime now,
    required int dayCutoffHour,
    int? courseId,
  });
}
