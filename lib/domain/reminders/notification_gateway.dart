import 'package:meta/meta.dart';
import 'package:timezone/timezone.dart' as tz;

/// One concrete OS notification, produced by the pure scheduler in
/// `reminder_scheduler.dart`. Everything the platform needs is on the value;
/// no subscription bookkeeping crosses this boundary.
@immutable
class ScheduledReminder {
  const new({
    required this.id,
    required this.title,
    required this.body,
    required this.firstFireTime,
    required this.weekday,
    required this.payload,
  });

  /// Deterministic 32-bit id from `notificationId(...)` (plan §4); scheduling
  /// the same id replaces the previous notification.
  final int id;

  final String title;
  final String body;

  /// First occurrence; always strictly in the future.
  final tz.TZDateTime firstFireTime;

  /// Weekday recurrence as dayIdx (0 = Monday … 6 = Sunday, plan §4); `null`
  /// recurs every day (`DateTimeComponents.time`), a value recurs weekly on
  /// that weekday (`DateTimeComponents.dayOfWeekAndTime`).
  final int? weekday;

  /// JSON string (plan §3.4), e.g. `{"scope":"course","courseId":5}`.
  final String payload;

  @override
  bool operator ==(Object other) =>
      other is ScheduledReminder &&
      other.id == id &&
      other.title == title &&
      other.body == body &&
      other.firstFireTime == firstFireTime &&
      other.weekday == weekday &&
      other.payload == payload;

  @override
  int get hashCode =>
      Object.hash(id, title, body, firstFireTime, weekday, payload);

  @override
  String toString() => 'ScheduledReminder(id: $id, title: $title, '
      'firstFireTime: $firstFireTime, weekday: $weekday)';
}

/// The only dependency the domain has on `flutter_local_notifications`. The
/// concrete implementation lives in `lib/data/notifications/` so the scheduler
/// and the reconciliation logic stay pure and unit-testable.
abstract class NotificationGateway {
  /// One-time plugin initialization. [onReminderTap] receives the raw payload
  /// for every delivery path (foreground/background callback AND cold start
  /// via `getNotificationAppLaunchDetails()`); routing is the caller's job.
  Future<void> initialize({
    required void Function(String payload) onReminderTap,
  });

  /// Cancels every pending reminder. The reconciliation rule (plan §1) starts
  /// from here and reschedules from the database, so "what the OS holds" is
  /// never tracked piecewise.
  Future<void> cancelAll();

  /// Schedules [reminder]; the same [ScheduledReminder.id] replaces.
  Future<void> schedule(ScheduledReminder reminder);

  /// Ids the OS currently holds — verification/debug only (plan §1).
  Future<List<int>> pendingReminderIds();
}
