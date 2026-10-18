import 'package:flashcards2/data/notifications/reminder_time_zone.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  group('initReminderTimeZone', () {
    test('sets tz.local to the device time zone', () async {
      await initReminderTimeZone(
        deviceTimeZoneIdentifier: () async => 'America/Los_Angeles',
      );

      expect(tz.local.name, 'America/Los_Angeles');
    });

    test('falls back to UTC when the platform lookup fails', () async {
      await initReminderTimeZone(
        deviceTimeZoneIdentifier: () async =>
            throw Exception('platform channel unavailable'),
      );

      expect(tz.local.name, 'UTC');
    });

    test('falls back to UTC for an identifier missing from the tzdb', () async {
      await initReminderTimeZone(
        deviceTimeZoneIdentifier: () async => 'Not/AZone',
      );

      expect(tz.local.name, 'UTC');
    });
  });
}
