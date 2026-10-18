import 'package:flashcards2/domain/reminders/notification_gateway.dart';
import 'package:flashcards2/domain/reminders/reminder_repository.dart';
import 'package:flashcards2/domain/reminders/reminder_scheduler.dart';
import 'package:timezone/timezone.dart' as tz;

/// The canonical rescheduling rule of plan §1: the database is the single
/// source of truth, so every relevant change (subscription edited, target
/// deleted — the cascade empties the plan — or app start) cancels everything
/// and reschedules from the DB. "What the OS currently holds" is never
/// tracked piecewise.
class ReminderSync {
  const new({required this.reminders, required this.gateway});

  final ReminderRepository reminders;
  final NotificationGateway gateway;

  /// Rebuilds the OS schedule; returns the applied plan so callers and tests
  /// can verify exactly what was scheduled. Target names must be passed
  /// resolved — the pure scheduler never performs IO.
  Future<List<ScheduledReminder>> rescheduleFromDatabase({
    required Map<int, String> courseNames,
    required Map<int, String> themeNames,
    required tz.TZDateTime now,
  }) async {
    final subscriptions = await reminders.findAll();
    final plan = planReminders(
      subscriptions: subscriptions,
      courseNames: courseNames,
      themeNames: themeNames,
      now: now,
    );
    await gateway.cancelAll();
    for (final scheduled in plan) {
      await gateway.schedule(scheduled);
    }
    return plan;
  }
}
