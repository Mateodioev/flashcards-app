import 'package:flashcards2/domain/reminders/notification_gateway.dart';
import 'package:flashcards2/domain/reminders/reminder.dart';
import 'package:flashcards2/domain/reminders/reminder_repository.dart';

/// Saves a reminder subscription applying the T5 permission flow (S10):
/// enabling first checks OS access, requests the runtime permission once if
/// it is merely unasked, and — on denial or a muted channel — still saves
/// the row but disabled, so later re-granting is a flip instead of data
/// loss. Turning a reminder off never touches the OS.
///
/// Returns the persisted subscription and the final access state so the UI
/// can explain a denial and offer the settings deep-link.
Future<({ReminderSubscription saved, ReminderAccess access})>
    saveReminderWithAccess({
  required ReminderRepository repository,
  required NotificationGateway gateway,
  required ReminderSubscription draft,
}) async {
  if (!draft.enabled) {
    final saved = await repository.upsert(draft);
    return (saved: saved, access: await gateway.accessState());
  }

  var access = await gateway.accessState();
  if (access == ReminderAccess.permissionDenied) {
    final granted = await gateway.requestNotificationPermission();
    access = granted
        ? await gateway.accessState()
        : ReminderAccess.permissionDenied;
  }

  final deliverable = access == ReminderAccess.granted;
  final saved = await repository.upsert(
    deliverable ? draft : draft.copyWith(enabled: false),
  );
  return (saved: saved, access: access);
}
