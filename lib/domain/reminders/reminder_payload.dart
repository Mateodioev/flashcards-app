import 'dart:convert';

import 'package:flashcards2/domain/reminders/reminder.dart';

/// Serializes the tap payload (docs/reminder_notifications_plan.md §3.4,
/// S11): `{"scope":"course","courseId":5}`. `scope` is always present;
/// `courseId`/`themeId` only for their scope, so global payloads carry no id
/// key at all.
String encodeReminderPayload(ReminderScope scope, int? targetId) {
  final payload = <String, Object?>{'scope': scope.name};
  switch (scope) {
    case ReminderScope.global:
      break;
    case ReminderScope.course:
      payload['courseId'] = targetId;
    case ReminderScope.theme:
      payload['themeId'] = targetId;
  }
  return jsonEncode(payload);
}

/// Inverse of [encodeReminderPayload]. Returns `null` on ANY malformed or
/// unknown input: OS-delivered payloads are untrusted bytes (stale version of
/// the app, tampered notification), never let them flow into navigation.
({ReminderScope scope, int? targetId})? decodeReminderPayload(String payload) {
  final Object? decoded;
  try {
    decoded = jsonDecode(payload);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) return null;
  final scopeName = decoded['scope'];
  if (scopeName is! String) return null;
  switch (scopeName) {
    case 'global':
      return (scope: ReminderScope.global, targetId: null);
    case 'course':
      final id = decoded['courseId'];
      if (id is! int) return null;
      return (scope: ReminderScope.course, targetId: id);
    case 'theme':
      final id = decoded['themeId'];
      if (id is! int) return null;
      return (scope: ReminderScope.theme, targetId: id);
    default:
      return null;
  }
}
