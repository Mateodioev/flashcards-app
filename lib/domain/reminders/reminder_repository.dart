import 'package:flashcards2/domain/reminders/reminder.dart';

/// Persistence contract for reminder subscriptions. The drift implementation
/// is the single source of truth that reconciliation reschedules from
/// (plan §1).
abstract class ReminderRepository {
  /// All subscriptions; the reminder-settings screen watches this.
  Stream<List<ReminderSubscription>> watchAll();

  Future<List<ReminderSubscription>> findAll();

  /// Inserts or replaces the one subscription per (scope, target) key
  /// (plan §2), matching on `scope`+`targetId` and ignoring `subscription.id`.
  Future<ReminderSubscription> upsert(ReminderSubscription subscription);

  Future<void> delete(int id);
}
