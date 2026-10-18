import 'package:flashcards2/domain/reminders/notification_gateway.dart';
import 'package:flashcards2/domain/reminders/reminder.dart';
import 'package:flashcards2/domain/reminders/reminder_access.dart';
import 'package:flashcards2/domain/reminders/reminder_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scripted fake: access state is a queue so a test can say "denied at
/// first, granted after the request". Requests are counted because asking
/// the OS is only allowed when the user tries to enable (plan T5).
class _ScriptedGateway implements NotificationGateway {
  new({required this.states, this.requestResults = const [false]});

  final List<ReminderAccess> states;
  final List<bool> requestResults;
  int _stateIndex = 0;
  int requests = 0;

  @override
  Future<ReminderAccess> accessState() async =>
      states[(_stateIndex++).clamp(0, states.length - 1)];

  @override
  Future<bool> requestNotificationPermission() async {
    requests++;
    return requestResults.first;
  }

  @override
  Future<void> initialize({
    required void Function(String payload) onReminderTap,
  }) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> schedule(ScheduledReminder reminder) async {}

  @override
  Future<List<int>> pendingReminderIds() async => const [];
}

class _RecordingReminderRepository implements ReminderRepository {
  final List<ReminderSubscription> upserts = [];

  @override
  Future<ReminderSubscription> upsert(
    ReminderSubscription subscription,
  ) async {
    upserts.add(subscription);
    return subscription;
  }

  @override
  Future<List<ReminderSubscription>> findAll() async => const [];

  @override
  Stream<List<ReminderSubscription>> watchAll() => const Stream.empty();

  @override
  Future<void> delete(int id) async {}
}

const _draft = ReminderSubscription(
  scope: ReminderScope.course,
  targetId: 3,
  hour: 9,
  minute: 15,
);

void main() {
  test('granted access saves the reminder enabled without asking the OS',
      () async {
    final gateway = _ScriptedGateway(states: [ReminderAccess.granted]);
    final repo = _RecordingReminderRepository();

    final result = await saveReminderWithAccess(
      repository: repo,
      gateway: gateway,
      draft: _draft,
    );

    expect(result.saved.enabled, isTrue);
    expect(result.access, ReminderAccess.granted);
    expect(gateway.requests, 0,
        reason: 'granted state needs no permission dialog');
  });

  test('first enable asks once and enables when the OS grants', () async {
    final gateway = _ScriptedGateway(
      states: [ReminderAccess.permissionDenied, ReminderAccess.granted],
      requestResults: [true],
    );
    final repo = _RecordingReminderRepository();

    final result = await saveReminderWithAccess(
      repository: repo,
      gateway: gateway,
      draft: _draft,
    );

    expect(gateway.requests, 1);
    expect(result.saved.enabled, isTrue);
    expect(result.access, ReminderAccess.granted);
  });

  test('denial keeps the subscription but stores it disabled (S10)',
      () async {
    final gateway = _ScriptedGateway(
      states: [
        ReminderAccess.permissionDenied,
        ReminderAccess.permissionDenied,
      ],
      requestResults: [false],
    );
    final repo = _RecordingReminderRepository();

    final result = await saveReminderWithAccess(
      repository: repo,
      gateway: gateway,
      draft: _draft,
    );

    expect(result.saved.enabled, isFalse,
        reason: 'the row survives so re-granting is a flip, not data loss');
    expect(result.access, ReminderAccess.permissionDenied);
  });

  test('a disabled channel after a granted permission stays disabled + '
      'reported as channelDisabled', () async {
    final gateway = _ScriptedGateway(
      states: [
        ReminderAccess.permissionDenied,
        ReminderAccess.channelDisabled,
      ],
      requestResults: [true],
    );
    final repo = _RecordingReminderRepository();

    final result = await saveReminderWithAccess(
      repository: repo,
      gateway: gateway,
      draft: _draft,
    );

    expect(result.saved.enabled, isFalse);
    expect(result.access, ReminderAccess.channelDisabled,
        reason: 'only the OS settings deep-link can recover this state');
  });

  test('turning a reminder off never queries the OS', () async {
    final gateway = _ScriptedGateway(states: [ReminderAccess.granted]);
    final repo = _RecordingReminderRepository();

    final result = await saveReminderWithAccess(
      repository: repo,
      gateway: gateway,
      draft: _draft.copyWith(enabled: false),
    );

    expect(result.saved.enabled, isFalse);
    expect(gateway.requests, 0);
  });
}
