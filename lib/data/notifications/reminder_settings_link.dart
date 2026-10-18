import 'package:app_settings/app_settings.dart';

/// T5/S10 recovery path: opens the app's own notification settings screen,
/// where Android shows both the master switch and the `study_reminders`
/// channel row. There is no API to re-enable a muted channel — this
/// deep-link is the only remedy, so the UI offers it on denial states.
/// `asAnotherTask` lets the user return to the app with Back afterwards.
Future<void> openNotificationSettingsForReminders() {
  return AppSettings.openAppSettings(
    type: AppSettingsType.notification,
    asAnotherTask: true,
  );
}
