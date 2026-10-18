import 'package:drift/native.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/data/notifications/reminder_time_zone.dart';
import 'package:flashcards2/data/repositories/drift_course_repository.dart';
import 'package:flashcards2/data/repositories/drift_reminder_repository.dart';
import 'package:flashcards2/domain/entities/course.dart';
import 'package:flashcards2/domain/reminders/notification_gateway.dart';
import 'package:flashcards2/domain/reminders/reminder.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flashcards2/presentation/screens/reminder_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/authoring.dart';

/// Scripted access state, no platform channels touched. Scheduling calls are
/// no-ops: the widget tests assert persistence and rendering, not OS state.
class _FakeGateway implements NotificationGateway {
  ReminderAccess access = ReminderAccess.granted;

  @override
  Future<ReminderAccess> accessState() async => access;

  @override
  Future<bool> requestNotificationPermission() async => false;

  @override
  Future<void> initialize({
    required void Function(String payload) onReminderTap,
  }) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> schedule(ScheduledReminder reminder) async {}

  @override
  Future<List<int>> pendingReminderIds() async => const <int>[];
}

void main() {
  late AppDatabase db;
  late _FakeGateway gateway;

  DriftReminderRepository reminders() => DriftReminderRepository(db);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    gateway = _FakeGateway();
    // The save flow reconciles with tz.TZDateTime.now(tz.local); without a
    // platform channel the device lookup is injected away (same as T1's
    // fallback path in main).
    await initReminderTimeZone(deviceTimeZoneIdentifier: () async => 'UTC');
  });
  tearDown(() => db.close());

  Widget app() {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        notificationGatewayProvider.overrideWithValue(gateway),
      ],
      child: const MaterialApp(home: ReminderSettingsScreen()),
    );
  }

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle();

  /// Drift schedules a zero-duration timer when a watched stream is
  /// cancelled (provider disposal on unmount); if that first happens in the
  /// framework's post-body teardown frame, `flutter_test` fails on a pending
  /// timer. Unmounting the tree inside the body flushes it deterministically.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  Future<Course> seedCourse(String name, {bool archived = false}) {
    return seedAuthoringCourse(
      DriftCourseRepository(db),
      name,
      archived: archived,
    );
  }

  group('list', () {
    testWidgets('empty state renders with the add affordance', (tester) async {
      await tester.pumpWidget(app());
      await settle(tester);

      expect(find.text('Reminders'), findsWidgets);
      expect(find.text('No reminders yet'), findsOneWidget);
      expect(find.text('Add reminder'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a seeded row shows target name, time and switch state', (
      tester,
    ) async {
      final course = await seedCourse('Biology');
      await reminders().upsert(
        ReminderSubscription(
          scope: ReminderScope.course,
          targetId: course.id,
          hour: 9,
          minute: 30,
        ),
      );
      await reminders().upsert(
        const ReminderSubscription(
          scope: ReminderScope.global,
          hour: 18,
          minute: 0,
          enabled: false,
        ),
      );

      await tester.pumpWidget(app());
      await settle(tester);

      expect(find.text('Biology'), findsOneWidget);
      expect(find.text('Everything'), findsOneWidget);
      expect(find.textContaining('09:30'), findsOneWidget);
      expect(find.textContaining('18:00'), findsOneWidget);

      final switches = tester
          .widgetList<Switch>(find.byType(Switch))
          .map((w) => w.value)
          .toList();
      expect(switches, contains(true), reason: 'course row enabled');
      expect(switches, contains(false), reason: 'global row disabled');
      await unmount(tester);
    });

    testWidgets('archived course reminder is listed with the marker', (
      tester,
    ) async {
      final course = await seedCourse('History', archived: true);
      await reminders().upsert(
        ReminderSubscription(
          scope: ReminderScope.course,
          targetId: course.id,
          hour: 8,
          minute: 0,
        ),
      );

      await tester.pumpWidget(app());
      await settle(tester);

      expect(find.text('History (archived)'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('toggling', () {
    testWidgets('switching off persists through the save flow and repumps', (
      tester,
    ) async {
      await reminders().upsert(
        const ReminderSubscription(
          scope: ReminderScope.global,
          hour: 18,
          minute: 0,
        ),
      );

      await tester.pumpWidget(app());
      await settle(tester);

      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      await tester.tap(find.byType(Switch));
      await settle(tester);

      final rows = await reminders().findAll();
      expect(rows.single.enabled, isFalse, reason: 'persisted off');
      expect(
        tester.widget<Switch>(find.byType(Switch)).value,
        isFalse,
        reason: 'the repumped row reflects the stored state',
      );
      await unmount(tester);
    });
  });

  group('access banner (T5)', () {
    testWidgets('channelDisabled shows the notice and the deep-link button', (
      tester,
    ) async {
      gateway.access = ReminderAccess.channelDisabled;

      await tester.pumpWidget(app());
      await settle(tester);

      expect(
        find.textContaining('will not fire'),
        findsOneWidget,
        reason: 'the banner explains reminders cannot announce',
      );
      expect(find.text('Open notification settings'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('permissionDenied also offers the deep-link', (tester) async {
      gateway.access = ReminderAccess.permissionDenied;

      await tester.pumpWidget(app());
      await settle(tester);

      expect(find.textContaining('will not fire'), findsOneWidget);
      expect(find.text('Open notification settings'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('granted access shows no banner', (tester) async {
      await tester.pumpWidget(app());
      await settle(tester);

      expect(find.text('Open notification settings'), findsNothing);
      await unmount(tester);
    });
  });
}
