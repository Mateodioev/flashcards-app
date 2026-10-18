import 'package:flashcards2/domain/reminders/reminder.dart';
import 'package:flashcards2/domain/reminders/reminder_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/New_York'));
  });

  tz.TZDateTime at(int year, int month, int day, [int hour = 0, int min = 0]) {
    return tz.TZDateTime(tz.local, year, month, day, hour, min);
  }

  group('notificationId (plan §4)', () {
    test('global daily reminder uses dayIdx 0', () {
      expect(notificationId(ReminderScope.global, null, 0), 0);
    });

    test('global weekly range is exactly 0–6', () {
      expect(notificationId(ReminderScope.global, null, 0), 0);
      expect(notificationId(ReminderScope.global, null, 6), 6);
    });

    test('course ids are 1_000_000 + targetId×10 + dayIdx', () {
      expect(notificationId(ReminderScope.course, 5, 0), 1000050);
      expect(notificationId(ReminderScope.course, 5, 6), 1000056);
      expect(notificationId(ReminderScope.course, 12, 3), 1000123);
    });

    test('theme ids are 1_000_000_000 + targetId×10 + dayIdx', () {
      expect(notificationId(ReminderScope.theme, 5, 0), 1000000050);
      expect(notificationId(ReminderScope.theme, 5, 6), 1000000056);
    });

    test('global ignores targetId', () {
      expect(notificationId(ReminderScope.global, 42, 3), 3);
    });

    test('asserts dayIdx is 0–6', () {
      expect(
        () => notificationId(ReminderScope.global, null, 7),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => notificationId(ReminderScope.global, null, -1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('asserts targetId for course and theme', () {
      expect(
        () => notificationId(ReminderScope.course, null, 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => notificationId(ReminderScope.theme, null, 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('ids are unique across scopes and weekdays', () {
      final ids = <int>{
        for (var d = 0; d <= 6; d++)
          notificationId(ReminderScope.global, null, d),
        for (var d = 0; d <= 6; d++)
          notificationId(ReminderScope.course, 1, d),
        for (var d = 0; d <= 6; d++)
          notificationId(ReminderScope.theme, 1, d),
        for (var d = 0; d <= 6; d++)
          notificationId(ReminderScope.course, 2, d),
        for (var d = 0; d <= 6; d++)
          notificationId(ReminderScope.theme, 2, d),
      };
      expect(ids, hasLength(35));
    });
  });

  group('nextFireTime', () {
    test('daily time later today fires today', () {
      final now = at(2026, 6, 15, 10); // Monday 10:00
      final fire = nextFireTime(hour: 18, minute: 0, dayIdx: null, now: now);
      expect(fire, at(2026, 6, 15, 18));
      expect(fire.isAfter(now), isTrue);
    });

    test('daily time already passed today fires tomorrow', () {
      final now = at(2026, 6, 15, 19);
      final fire = nextFireTime(hour: 18, minute: 0, dayIdx: null, now: now);
      expect(fire, at(2026, 6, 16, 18));
    });

    test('daily time exactly now fires tomorrow (strictly after)', () {
      final now = at(2026, 6, 15, 18);
      final fire = nextFireTime(hour: 18, minute: 0, dayIdx: null, now: now);
      expect(fire, at(2026, 6, 16, 18));
    });

    test('weekly on a later weekday fires that weekday this week', () {
      final now = at(2026, 6, 15, 19); // Monday
      final fire = nextFireTime(hour: 18, minute: 0, dayIdx: 2, now: now);
      expect(fire, at(2026, 6, 17, 18)); // Wednesday
      expect(fire.weekday, 3);
      expect(fire.isAfter(now), isTrue);
    });

    test('weekly today with time still ahead fires today', () {
      final now = at(2026, 6, 15, 10); // Monday 10:00
      final fire = nextFireTime(hour: 18, minute: 0, dayIdx: 0, now: now);
      expect(fire, at(2026, 6, 15, 18));
    });

    test('weekly today with time passed fires next week', () {
      final now = at(2026, 6, 15, 19); // Monday 19:00
      final fire = nextFireTime(hour: 18, minute: 0, dayIdx: 0, now: now);
      expect(fire, at(2026, 6, 22, 18)); // next Monday
      expect(fire.isAfter(now), isTrue);
    });

    test('weekly wraps around the weekend', () {
      final now = at(2026, 6, 20, 19); // Saturday (weekday 6)
      final fire = nextFireTime(hour: 9, minute: 30, dayIdx: 6, now: now);
      expect(fire, at(2026, 6, 21, 9, 30)); // Sunday
      expect(fire.weekday, 7);
    });

    test('DST spring forward: 04:30 on 2026-03-08 keeps wall time 04:30', () {
      // In America/New_York, 2026-03-08 springs forward 02:00 → 03:00, so
      // wall 04:30 exists only as EDT (offset −04:00). Naively adding 24h
      // across the transition would land on 05:30 — the bug this rules out.
      final now = at(2026, 3, 7, 4, 30); // Saturday 04:30 EST
      final fire = nextFireTime(hour: 4, minute: 30, dayIdx: null, now: now);
      expect(fire.day, 8);
      expect(fire.hour, 4);
      expect(fire.minute, 30);
      expect(fire.timeZone.offset, const Duration(hours: -4));
      expect(fire.isAfter(now), isTrue);
    });

    test('weekly 18:00 keeps wall time 18:00 across the transition', () {
      final now = at(2026, 3, 6, 19); // Friday 19:00 EST
      final fire = nextFireTime(hour: 18, minute: 0, dayIdx: 4, now: now);
      expect(fire.day, 13); // next Friday, already EDT
      expect(fire.hour, 18);
      expect(fire.minute, 0);
      expect(fire.timeZone.offset, const Duration(hours: -4));
    });

    test('DST fall back: result is still in the future and wall-pinned', () {
      // 2026-11-01 falls back 02:00 EDT → 01:00 EST.
      final now = at(2026, 10, 31, 19); // Saturday before the fall back
      final fire = nextFireTime(hour: 18, minute: 0, dayIdx: 6, now: now);
      expect(fire.day, 1);
      expect(fire.month, 11);
      expect(fire.hour, 18);
      expect(fire.timeZone.offset, const Duration(hours: -5));
      expect(fire.isAfter(now), isTrue);
    });
  });

  group('planReminders', () {
    // Lazy: tz.local is only set inside setUpAll, so eager fields must not
    // read it at declaration time.
    late final now = tz.TZDateTime(tz.local, 2026, 6, 15, 10); // Mon 10:00

    ReminderSubscription sub({
      ReminderScope scope = ReminderScope.global,
      int? targetId,
      List<int>? daysOfWeek,
      bool enabled = true,
    }) {
      return ReminderSubscription(
        scope: scope,
        targetId: targetId,
        hour: 18,
        minute: 0,
        daysOfWeek: daysOfWeek,
        enabled: enabled,
      );
    }

    test('disabled subscriptions are excluded', () {
      final plan = planReminders(
        subscriptions: [sub(enabled: false)],
        courseNames: const {},
        themeNames: const {},
        now: now,
      );
      expect(plan, isEmpty);
    });

    test('course subscriptions with a missing name are skipped (ghosts)', () {
      final plan = planReminders(
        subscriptions: [sub(scope: ReminderScope.course, targetId: 99)],
        courseNames: const {1: 'Intro'},
        themeNames: const {},
        now: now,
      );
      expect(plan, isEmpty);
    });

    test('theme subscriptions with a missing name are skipped (ghosts)', () {
      final plan = planReminders(
        subscriptions: [sub(scope: ReminderScope.theme, targetId: 99)],
        courseNames: const {},
        themeNames: const {1: 'Verbs'},
        now: now,
      );
      expect(plan, isEmpty);
    });

    test('daily subscription yields one reminder with weekday null', () {
      final plan = planReminders(
        subscriptions: [sub()],
        courseNames: const {},
        themeNames: const {},
        now: now,
      );
      expect(plan, hasLength(1));
      final r = plan.single;
      expect(r.id, notificationId(ReminderScope.global, null, 0));
      expect(r.weekday, isNull);
      expect(r.firstFireTime.isAfter(now), isTrue);
    });

    test('weekly subscription fans out one reminder per dayIdx', () {
      final plan = planReminders(
        subscriptions: [sub(daysOfWeek: [0, 2])],
        courseNames: const {},
        themeNames: const {},
        now: now,
      );
      expect(plan, hasLength(2));
      expect(plan[0].id, notificationId(ReminderScope.global, null, 0));
      expect(plan[0].weekday, 0);
      expect(plan[1].id, notificationId(ReminderScope.global, null, 2));
      expect(plan[1].weekday, 2);
      final ids = plan.map((r) => r.id).toSet();
      expect(ids, hasLength(2));
    });

    test('static bodies per scope (plan §2, D1)', () {
      final plan = planReminders(
        subscriptions: [
          sub(),
          sub(scope: ReminderScope.course, targetId: 1),
          sub(scope: ReminderScope.theme, targetId: 7),
        ],
        courseNames: const {1: 'Intro'},
        themeNames: const {7: 'Verbs'},
        now: now,
      );
      expect(plan, hasLength(3));
      for (final r in plan) {
        expect(r.title, 'Flashcards');
      }
      final byId = {for (final r in plan) r.id: r};
      expect(byId[0]!.body, 'Time to review your flashcards');
      expect(byId[1000010]!.body, 'Time to review: Intro');
      expect(byId[1000000070]!.body, 'Time to review: Verbs');
    });

    test('payload is embedded as the encoded JSON', () {
      final plan = planReminders(
        subscriptions: [sub(scope: ReminderScope.course, targetId: 5)],
        courseNames: const {5: 'Math'},
        themeNames: const {},
        now: now,
      );
      expect(plan.single.payload, '{"scope":"course","courseId":5}');
    });

    test('global payload carries no id key', () {
      final plan = planReminders(
        subscriptions: [sub()],
        courseNames: const {},
        themeNames: const {},
        now: now,
      );
      expect(plan.single.payload, '{"scope":"global"}');
    });

    test('output is sorted deterministically by id', () {
      final plan = planReminders(
        subscriptions: [
          sub(scope: ReminderScope.theme, targetId: 7),
          sub(scope: ReminderScope.course, targetId: 1),
          sub(),
        ],
        courseNames: const {1: 'Intro'},
        themeNames: const {7: 'Verbs'},
        now: now,
      );
      final ids = plan.map((r) => r.id).toList();
      expect(ids, [
        notificationId(ReminderScope.global, null, 0),
        notificationId(ReminderScope.course, 1, 0),
        notificationId(ReminderScope.theme, 7, 0),
      ]);
    });
  });
}
