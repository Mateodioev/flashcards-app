import 'package:drift/drift.dart';
import 'package:flashcards2/data/daos/review_log_dao.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/domain/entities/scheduling.dart';
import 'package:flashcards2/domain/repositories/review_log_repository.dart';

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
