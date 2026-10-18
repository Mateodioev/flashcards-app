import 'package:flashcards2/domain/reminders/notification_gateway.dart';
import 'package:flashcards2/domain/reminders/reminder.dart';
import 'package:flashcards2/domain/reminders/reminder_repository.dart';
import 'package:flashcards2/domain/reminders/reminder_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Fakes for the reconciliation orchestration: the gateway records calls,
/// the repository is an in-memory map. The point of these tests is the
/// canonical rule of plan §1 — cancel everything, reschedule from the DB.
class _FakeGateway implements NotificationGateway {
  int cancelAllCalls = 0;
  final List<ScheduledReminder> scheduled = [];

  @override
  Future<void> initialize({
    required void Function(String payload) onReminderTap,
  }) async {}

  @override
  Future<void> cancelAll() async => cancelAllCalls++;

  @override
  Future<void> schedule(ScheduledReminder reminder) async {
    scheduled.add(reminder);
  }

  @override
  Future<List<int>> pendingReminderIds() async => [
        for (final reminder in scheduled) reminder.id,
      ];
}

class _FakeReminderRepository implements ReminderRepository {
  new(this._rows);

  final List<ReminderSubscription> _rows;

  @override
  Future<List<ReminderSubscription>> findAll() async => _rows;

  @override
  Stream<List<ReminderSubscription>> watchAll() =>
      Stream.value(_rows);

  @override
  Future<ReminderSubscription> upsert(
    ReminderSubscription subscription,
  ) async =>
      subscription;

  @override
  Future<void> delete(int id) async {}
}

void main() {
  late tz.TZDateTime now;

  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('UTC'));
    now = tz.TZDateTime(tz.local, 2026, 3, 1, 9);
  });

  test('cancels everything, then schedules the planned reminders (S1)',
      () async {
    final gateway = _FakeGateway();
    final repo = _FakeReminderRepository(const [
      ReminderSubscription(scope: ReminderScope.global, hour: 18, minute: 0),
    ]);
    final sync = ReminderSync(reminders: repo, gateway: gateway);

    final plan = await sync.rescheduleFromDatabase(
      courseNames: const {},
      themeNames: const {},
      now: now,
    );

    expect(gateway.cancelAllCalls, 1,
        reason: 'reconciliation always starts from a clean slate');
    expect(gateway.scheduled, plan);
    expect(plan, hasLength(1), reason: 'one daily global reminder');
  });

  test('schedules nothing when every subscription is disabled', () async {
    final gateway = _FakeGateway();
    final sync = ReminderSync(
      reminders: _FakeReminderRepository(const [
        ReminderSubscription(
          scope: ReminderScope.global,
          hour: 18,
          minute: 0,
          enabled: false,
        ),
      ]),
      gateway: gateway,
    );

    final plan = await sync.rescheduleFromDatabase(
      courseNames: const {},
      themeNames: const {},
      now: now,
    );

    expect(gateway.cancelAllCalls, 1);
    expect(gateway.scheduled, isEmpty);
    expect(plan, isEmpty);
  });

  test('course and theme names flow into the scheduled bodies', () async {
    final gateway = _FakeGateway();
    final sync = ReminderSync(
      reminders: _FakeReminderRepository(const [
        ReminderSubscription(
          scope: ReminderScope.course,
          targetId: 5,
          hour: 18,
          minute: 0,
        ),
        ReminderSubscription(
          scope: ReminderScope.theme,
          targetId: 7,
          hour: 18,
          minute: 0,
        ),
      ]),
      gateway: gateway,
    );

    await sync.rescheduleFromDatabase(
      courseNames: const {5: 'Biology'},
      themeNames: const {7: 'Cells'},
      now: now,
    );

    final bodies = gateway.scheduled.map((r) => r.body).toList();
    expect(
      bodies,
      containsAll(['Time to review: Biology', 'Time to review: Cells']),
    );
  });
}
