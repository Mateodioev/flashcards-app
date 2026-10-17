import 'package:drift/drift.dart';
import 'package:flashcards2/data/daos/review_log_dao.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/domain/entities/scheduling.dart';
import 'package:flashcards2/domain/repositories/review_log_repository.dart';
import 'package:flashcards2/domain/scheduling/scheduler.dart';

/// Drift-backed [ReviewLogRepository].
///
/// Exposes append and read only — matching the append-only contract. There is
/// no way to mutate a stored log through this class, by design.
class DriftReviewLogRepository implements ReviewLogRepository {
  new(AppDatabase db) : _dao = ReviewLogDao(db);

  final ReviewLogDao _dao;

  @override
  Future<ReviewLog> append(ReviewLog log) async {
    final row = await _dao.append(
      ReviewLogsCompanion.insert(
        cardId: log.cardId,
        rating: log.rating,
        reviewedAt: log.reviewedAt,
        state: log.state,
        elapsedDays: Value(log.elapsedDays),
        scheduledDays: Value(log.scheduledDays),
        durationMs: Value(log.durationMs),
        hintUsed: Value(log.hintUsed),
        barrierCompleted: Value(log.barrierCompleted),
      ),
    );
    return _toDomain(row);
  }

  @override
  Future<List<ReviewLog>> findByCard(int cardId, {int? limit}) async {
    final rows = await _dao.byCard(cardId, limit: limit);
    return rows.map(_toDomain).toList();
  }

  @override
  Future<List<ReviewLog>> findAll() async {
    final rows = await _dao.all();
    return rows.map(_toDomain).toList();
  }

  @override
  Future<List<ReviewLog>> recent({int? courseId, int limit = 50}) async {
    final rows = await _dao.recent(courseId: courseId, limit: limit);
    return rows.map(_toDomain).toList();
  }

  @override
  Future<int> countNewCardsIntroducedToday({
    required DateTime now,
    required int dayCutoffHour,
    int? courseId,
  }) async {
    final firstReviews = await _dao.firstReviewsByCourse();
    final today = Scheduler.dayIndex(now, dayCutoffHour);
    return firstReviews
        .where(
          (entry) =>
              (courseId == null || entry.courseId == courseId) &&
              Scheduler.dayIndex(entry.firstReview, dayCutoffHour) == today,
        )
        .length;
  }

  @override
  Future<Map<int, int>> countNewCardsIntroducedTodayByCourse({
    required DateTime now,
    required int dayCutoffHour,
  }) async {
    final firstReviews = await _dao.firstReviewsByCourse();
    final today = Scheduler.dayIndex(now, dayCutoffHour);
    final counts = <int, int>{};
    for (final entry in firstReviews) {
      if (Scheduler.dayIndex(entry.firstReview, dayCutoffHour) == today) {
        counts[entry.courseId] = (counts[entry.courseId] ?? 0) + 1;
      }
    }
    return counts;
  }

  ReviewLog _toDomain(ReviewLogRow row) {
    return ReviewLog(
      id: row.id,
      cardId: row.cardId,
      rating: row.rating,
      reviewedAt: row.reviewedAt,
      elapsedDays: row.elapsedDays,
      scheduledDays: row.scheduledDays,
      state: row.state,
      durationMs: row.durationMs,
      hintUsed: row.hintUsed,
      barrierCompleted: row.barrierCompleted,
    );
  }
}
