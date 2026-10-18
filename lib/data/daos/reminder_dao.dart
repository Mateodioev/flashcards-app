import 'package:drift/drift.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/data/tables/tables.dart';

part 'reminder_dao.g.dart';

/// Access to the `reminder_subscriptions` table.
///
/// Queries key off the `course_id`/`theme_id` columns rather than the scope
/// enum, which keeps this DAO free of `domain/` (the same convention as the
/// other DAOs). The table's CHECK constraint guarantees the pairing, so
/// "course-scoped" and "has a course_id" are the same set of rows.
@DriftAccessor(tables: [ReminderSubscriptions])
class ReminderDao extends DatabaseAccessor<AppDatabase>
    with _$ReminderDaoMixin {
  new(super.attachedDatabase);

  /// Every subscription, ordered by id so the settings list is stable.
  Future<List<ReminderSubscriptionRow>> findAll() {
    return (select(
      reminderSubscriptions,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
  }

  Stream<List<ReminderSubscriptionRow>> watchAll() {
    return (select(
      reminderSubscriptions,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).watch();
  }

  /// The (at most one, by repository convention) global subscription — the
  /// row with no target. `limit(1)` because the UNIQUE constraints cannot
  /// distinguish multiple all-null rows.
  Future<ReminderSubscriptionRow?> findGlobal() {
    return (select(reminderSubscriptions)
          ..where((t) => t.courseId.isNull() & t.themeId.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.id)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<ReminderSubscriptionRow?> findByCourseId(int courseId) {
    return (select(
      reminderSubscriptions,
    )..where((t) => t.courseId.equals(courseId))).getSingleOrNull();
  }

  Future<ReminderSubscriptionRow?> findByThemeId(int themeId) {
    return (select(
      reminderSubscriptions,
    )..where((t) => t.themeId.equals(themeId))).getSingleOrNull();
  }

  Future<ReminderSubscriptionRow?> findById(int id) {
    return (select(
      reminderSubscriptions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<ReminderSubscriptionRow> insertSubscription(
    ReminderSubscriptionsCompanion subscription,
  ) {
    return into(reminderSubscriptions).insertReturning(subscription);
  }

  Future<bool> updateSubscription(ReminderSubscriptionRow subscription) {
    return update(reminderSubscriptions).replace(subscription);
  }

  Future<int> deleteSubscription(int id) {
    return (delete(reminderSubscriptions)..where((t) => t.id.equals(id))).go();
  }
}
