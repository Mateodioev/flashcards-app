import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The debug and profile manifests declare INTERNET so `flutter run` always
/// has network, but the release manifest does not inherit it. A release build
/// without this declaration has no network at all and the AI import fails on
/// device with a socket error, despite every test having passed — flutter_test
/// cannot see an Android permission.
void main() {
  test('the release manifest declares INTERNET', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(
      manifest,
      contains('<uses-permission android:name="android.permission.INTERNET"'),
      reason: 'without it, release builds have no network at all',
    );
  });

  // Study reminders (docs/reminder_notifications_plan.md): these pin the
  // release-manifest contract because flutter_test cannot see Android
  // permissions — a missing declaration only fails on a physical device.
  group('study reminder notifications', () {
    String releaseManifest() =>
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    String permission(String name) =>
        '<uses-permission android:name="android.permission.$name"';

    test('declares POST_NOTIFICATIONS so reminders can be requested at runtime',
        () {
      expect(
        releaseManifest(),
        contains(permission('POST_NOTIFICATIONS')),
        reason: 'Android 13+ hides notifications without the runtime '
            'permission, and the manifest entry is the prerequisite',
      );
    });

    test('declares RECEIVE_BOOT_COMPLETED so reminders survive reboots', () {
      expect(
        releaseManifest(),
        contains(permission('RECEIVE_BOOT_COMPLETED')),
        reason: 'without it the plugin cannot restore scheduled reminders '
            'after a device reboot',
      );
    });

    test('does NOT declare SCHEDULE_EXACT_ALARM (plan D2: inexact delivery)',
        () {
      expect(
        releaseManifest(),
        isNot(contains('SCHEDULE_EXACT_ALARM')),
        reason: 'exact alarms need Play-store justification and degrade '
            'silently if the user revokes the permission; reminders are '
            'scheduled with AndroidScheduleMode.inexactAllowWhileIdle',
      );
    });

    test('ships the app_icon drawable used as the notification small icon', () {
      expect(
        File('android/app/src/main/res/drawable/app_icon.xml').existsSync(),
        isTrue,
        reason: "AndroidInitializationSettings('app_icon') requires a "
            'drawable resource or initialization fails on device',
      );
    });
  });
}
