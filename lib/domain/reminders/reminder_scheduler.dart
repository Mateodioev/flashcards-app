import 'package:flashcards2/domain/reminders/notification_gateway.dart';
import 'package:flashcards2/domain/reminders/reminder.dart';
import 'package:flashcards2/domain/reminders/reminder_payload.dart';
import 'package:timezone/timezone.dart' as tz;

const int _courseIdBase = 1000000;
const int _themeIdBase = 1000000000;

/// Deterministic 32-bit notification id (docs/reminder_notifications_plan.md
/// §4, S12): global owns 0–6, courses start at 1_000_000, themes at
/// 1_000_000_000. [dayIdx] is 0 = Monday … 6 = Sunday.
///
/// [ReminderScope.global] ignores [targetId]; daily reminders use dayIdx 0.
/// Course and theme scopes require a non-null [targetId].
int notificationId(ReminderScope scope, int? targetId, int dayIdx) {
  assert(dayIdx >= 0 && dayIdx <= 6, 'dayIdx must be 0 (Mon) … 6 (Sun)');
  switch (scope) {
    case ReminderScope.global:
      return dayIdx;
    case ReminderScope.course:
      assert(targetId != null, 'course reminders need a targetId');
      return _courseIdBase + targetId! * 10 + dayIdx;
    case ReminderScope.theme:
      assert(targetId != null, 'theme reminders need a targetId');
      return _themeIdBase + targetId! * 10 + dayIdx;
  }
}

/// `hour:minute` on `now`'s calendar day, used only to compare against `now`.
tz.TZDateTime _atToday(tz.TZDateTime now, int hour, int minute) {
  return tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
}

/// The next local occurrence of `hour:minute` strictly after [now] in
/// `tz.local`. With [dayIdx] (0 = Monday … 6 = Sunday), the next occurrence
/// of that weekday at `hour:minute` (tz weekday = dayIdx + 1).
///
/// Wall-clock safety: the candidate is built from calendar components, never
/// by adding 24-hour durations, so a reminder stays at its wall time across
/// DST transitions (see the spring-forward tests).
tz.TZDateTime nextFireTime({
  required int hour,
  required int minute,
  required int? dayIdx,
  required tz.TZDateTime now,
}) {
  var shiftDays = 0;
  if (dayIdx == null) {
    final today = _atToday(now, hour, minute);
    if (!today.isAfter(now)) shiftDays = 1;
  } else {
    final targetWeekday = dayIdx + 1; // plan §4: dayIdx 0 = Monday
    shiftDays = (targetWeekday - now.weekday) % 7;
    if (shiftDays == 0) {
      final today = _atToday(now, hour, minute);
      if (!today.isAfter(now)) shiftDays = 7;
    }
  }
  // Pure calendar arithmetic on proleptic UTC dates: offsets can't distort it.
  final target = DateTime.utc(now.year, now.month, now.day + shiftDays);
  return tz.TZDateTime(
    tz.local,
    target.year,
    target.month,
    target.day,
    hour,
    minute,
  );
}

/// Turns persisted subscriptions into concrete schedulable notifications
/// (S5): enabled subscriptions only, one per weekday for weekly reminders
/// and one (weekday `null`) for daily reminders.
///
/// Ghost defense (plan §7): a course/theme subscription whose target id is
/// missing from [courseNames]/[themeNames] is SKIPPED — the target may have
/// been deleted without the FK cascade having run yet, and scheduling a
/// nameless reminder would strand the user in an empty study session.
///
/// The result is sorted by [ScheduledReminder.id]. The reconciliation rule
/// (cancelAll + reschedule, plan §1) makes order irrelevant at runtime, but
/// determinism keeps tests and reviews honest.
List<ScheduledReminder> planReminders({
  required List<ReminderSubscription> subscriptions,
  required Map<int, String> courseNames,
  required Map<int, String> themeNames,
  required tz.TZDateTime now,
}) {
  final planned = <ScheduledReminder>[];
  for (final sub in subscriptions) {
    if (!sub.enabled) continue;
    final name = switch (sub.scope) {
      ReminderScope.global => '',
      ReminderScope.course => courseNames[sub.targetId],
      ReminderScope.theme => themeNames[sub.targetId],
    };
    if (name == null) continue; // ghost defense
    final body = switch (sub.scope) {
      ReminderScope.global => 'Time to review your flashcards',
      _ => 'Time to review: $name',
    };
    final payload = encodeReminderPayload(sub.scope, sub.targetId);
    final dayIndexes = sub.isDaily ? const [0] : sub.daysOfWeek!;
    for (final dayIdx in dayIndexes) {
      planned.add(
        ScheduledReminder(
          id: notificationId(sub.scope, sub.targetId, dayIdx),
          title: 'Flashcards',
          body: body,
          firstFireTime: nextFireTime(
            hour: sub.hour,
            minute: sub.minute,
            dayIdx: sub.isDaily ? null : dayIdx,
            now: now,
          ),
          weekday: sub.isDaily ? null : dayIdx,
          payload: payload,
        ),
      );
    }
  }
  planned.sort((a, b) => a.id.compareTo(b.id));
  return planned;
}
