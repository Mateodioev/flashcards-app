import 'package:flashcards2/domain/reminders/reminder.dart';
import 'package:flashcards2/domain/reminders/reminder_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('encodeReminderPayload (plan §3.4)', () {
    test('global carries only the scope', () {
      expect(
        encodeReminderPayload(ReminderScope.global, null),
        '{"scope":"global"}',
      );
    });

    test('course carries courseId', () {
      expect(
        encodeReminderPayload(ReminderScope.course, 5),
        '{"scope":"course","courseId":5}',
      );
    });

    test('theme carries themeId', () {
      expect(
        encodeReminderPayload(ReminderScope.theme, 7),
        '{"scope":"theme","themeId":7}',
      );
    });
  });

  group('decodeReminderPayload', () {
    test('round-trips global with no id key', () {
      final decoded = decodeReminderPayload('{"scope":"global"}');
      expect(decoded, isNotNull);
      expect(decoded!.scope, ReminderScope.global);
      expect(decoded.targetId, isNull);
    });

    test('round-trips course', () {
      final decoded = decodeReminderPayload(
        encodeReminderPayload(ReminderScope.course, 5),
      );
      expect(decoded, isNotNull);
      expect(decoded!.scope, ReminderScope.course);
      expect(decoded.targetId, 5);
    });

    test('round-trips theme', () {
      final decoded = decodeReminderPayload(
        encodeReminderPayload(ReminderScope.theme, 7),
      );
      expect(decoded, isNotNull);
      expect(decoded!.scope, ReminderScope.theme);
      expect(decoded.targetId, 7);
    });

    group('malformed or untrusted input returns null', () {
      for (final payload in [
        '',
        'not json',
        '[]',
        '42',
        '"course"',
        '{}',
        '{"scope":"banana"}',
        '{"scope":42}',
        '{"scope":"course"}',
        '{"scope":"course","courseId":"5"}',
        '{"scope":"theme","themeId":null}',
      ]) {
        test('payload: $payload', () {
          expect(decodeReminderPayload(payload), isNull);
        });
      }
    });
  });
}
