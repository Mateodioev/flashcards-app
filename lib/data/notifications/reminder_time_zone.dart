import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Initializes the TZDateTime database and points `tz.local` at the device
/// time zone. Scheduled reminders are only correct relative to the right
/// zone, and the `timezone` package cannot discover it by itself
/// (`flutter_timezone` wraps the platform call). A bad lookup must never
/// crash startup, so any failure degrades to UTC with a misaligned schedule
/// instead of a dead app — the app-start reconcile still runs.
Future<void> initReminderTimeZone({
  Future<String> Function()? deviceTimeZoneIdentifier,
}) async {
  tz_data.initializeTimeZones();

  String? identifier;
  try {
    final fetch = deviceTimeZoneIdentifier ??
        () async => (await FlutterTimezone.getLocalTimezone()).identifier;
    identifier = await fetch();
  } on Object {
    identifier = null;
  }

  tz.Location location;
  try {
    location = tz.getLocation(identifier ?? 'UTC');
  } on Object {
    location = tz.getLocation('UTC');
  }
  tz.setLocalLocation(location);
}
