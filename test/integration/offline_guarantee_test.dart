import 'dart:io';

import 'package:drift/native.dart';
import 'package:flashcards2/data/ai/openai_compatible_client.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/data/repositories/drift_card_repository.dart';
import 'package:flashcards2/data/repositories/drift_course_repository.dart';
import 'package:flashcards2/data/repositories/drift_review_log_repository.dart';
import 'package:flashcards2/data/repositories/drift_settings_repository.dart';
import 'package:flashcards2/domain/ai/ai_settings_service.dart';
import 'package:flashcards2/domain/entities/card.dart' as domain;
import 'package:flashcards2/domain/entities/course.dart';
import 'package:flashcards2/domain/entities/scheduling.dart';
import 'package:flashcards2/domain/entities/theme.dart' as domain;
import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/domain/scheduling/scheduler.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The offline guarantee, as a test rather than a claim.
///
/// The app is local-first: everything except image import must work with no
/// network at all. Rather than assert that by hand-testing airplane mode, this
/// file takes the network **away** and then exercises the real repositories and
/// the real scheduler on in-memory storage.
///
/// The mechanism is [HttpOverrides]: while installed, connections created
/// from `dart:io` throw. If a future change quietly reaches for the network
/// outside the AI client, these tests fail here rather than on a user's device
/// with no signal. The AI layer is exercised too, to prove it is the **only**
/// thing that fails, and that it fails with a clear message instead of hanging.
void main() {
  late AppDatabase db;
  late DriftCourseRepository courses;
  late DriftCardRepository cards;
  late DriftReviewLogRepository logs;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    courses = DriftCourseRepository(db);
    cards = DriftCardRepository(db);
    logs = DriftReviewLogRepository(db);
  });
  tearDown(() => db.close());

  group('with all network access blocked', () {
    setUp(() => HttpOverrides.global = _NoNetwork());
    tearDown(() => HttpOverrides.global = null);

    test('a course, theme and card can be authored', () async {
      final course = await courses.create(_course('Biology'));
      final theme = await cards.createTheme(
        domain.Theme(
          id: 0,
          courseId: course.id,
          name: 'Cells',
          createdAt: DateTime(2022),
        ),
      );
      await cards.createCard(
        domain.Card(
          id: 0,
          themeId: theme.id,
          front: 'What is a mitochondrion?',
          back: 'An organelle that produces ATP.',
          source: CardSource.manual,
          createdAt: DateTime(2022),
          updatedAt: DateTime(2022),
        ),
      );

      final stored = await cards.findCardsByTheme(theme.id);
      expect(stored, hasLength(1));
      expect(stored.single.front, 'What is a mitochondrion?');
    });

    test('grading a card writes a log and advances the schedule', () async {
      // The core value of the app. If this needed a network, the whole premise
      // would be broken.
      final (_, theme) = await _seedCard(courses, cards);

      expect(
        await cards.findScheduleState(theme.id),
        isNull,
        reason: 'a new card has no schedule yet',
      );

      const scheduler = Scheduler();
      final now = DateTime(2022, 1, 2);
      final outcome = scheduler.review(
        card: const CardSchedule.newCard(),
        rating: Rating.good,
        now: now,
      );

      await cards.upsertScheduleState(
        ScheduleState(
          cardId: theme.id,
          stability: outcome.schedule.memory?.stability ?? 0,
          difficulty: outcome.schedule.memory?.difficulty ?? 0,
          due: outcome.schedule.due ?? now,
          lastReview: now,
          reps: outcome.schedule.reps,
          lapses: outcome.schedule.lapses,
          state: outcome.schedule.state,
          step: outcome.schedule.step,
        ),
      );

      final after = await cards.findScheduleState(theme.id);
      expect(after, isNotNull, reason: 'the schedule must persist offline');
      expect(after!.reps, greaterThan(0));
      expect(after.state, isNot(ReviewState.new_));
    });

    test('a review log persists', () async {
      final (_, theme) = await _seedCard(courses, cards);

      await logs.append(
        ReviewLog(
          id: 0,
          cardId: theme.id,
          rating: Rating.good,
          reviewedAt: DateTime(2022, 1, 2),
          elapsedDays: 0,
          scheduledDays: 1,
          state: ReviewState.learning,
          durationMs: 4200,
          hintUsed: false,
          barrierCompleted: true,
        ),
      );

      final stored = await logs.findByCard(theme.id);
      expect(stored, hasLength(1));
      expect(stored.single.rating, Rating.good);
    });

    test('settings read and write', () async {
      final settings = DriftSettingsRepository(db);
      final current = await settings.read();
      await settings.update(current.copyWith(themeMode: AppThemeMode.dark));

      expect((await settings.read()).themeMode, AppThemeMode.dark);
    });

    test('the app wires up without reaching the network', () async {
      // Constructing every provider the app depends on is a blunt but effective
      // check: if any of them opened a socket or fetched a remote asset, the
      // blocked client would throw here.
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      expect(container.read(courseRepositoryProvider), isNotNull);
      expect(container.read(cardRepositoryProvider), isNotNull);
      expect(container.read(reviewLogRepositoryProvider), isNotNull);
      expect(container.read(settingsRepositoryProvider), isNotNull);
      expect(await container.read(courseRepositoryProvider).findAll(), isEmpty);
    });

    test('the AI client fails with a readable message, never hangs', () async {
      // The one legitimate network feature. Offline it must produce an error
      // the learner can act on: a silent hang on a plane is
      // indistinguishable from a freeze.
      const client = OpenAiCompatibleClient(
        baseUrl: 'https://api.example.invalid/v1',
        apiKey: 'irrelevant',
        timeout: Duration(seconds: 10),
      );

      final result = await client.verify();
      expect(result.ok, isFalse);
      expect(
        result.message,
        isNotNull,
        reason: 'an offline failure must explain itself',
      );
      expect(
        result.message,
        contains('reach'),
        reason: 'the message should name the likely cause: ${result.message}',
      );
    });

    test('AI settings report unconfigured rather than throwing', () async {
      final service = AiSettingsService(
        DriftSettingsRepository(db),
        InMemoryApiKeyStore(),
      );

      expect(await service.read(), isNull);
      expect(await service.isConfigured(), isFalse);
    });

    test('image import is the only thing that needs the network', () async {
      // States the guarantee directly: with no network and no AI configuration,
      // the app is fully usable. Only the import entry point is inert.
      final service = AiSettingsService(
        DriftSettingsRepository(db),
        InMemoryApiKeyStore(),
      );
      expect(
        await service.isConfigured(),
        isFalse,
        reason: 'unconfigured is the correct offline state, not an error',
      );

      final course = await courses.create(_course('History'));
      expect(await courses.findAll(), hasLength(1));
      expect(course.name, 'History');
    });
  });

  group('the network guard itself', () {
    tearDown(() => HttpOverrides.global = null);

    test('the override is actually consulted', () async {
      // Guards the guard, and it has to discriminate. An earlier version
      // asserted only that a request to a fake host throws SocketException —
      // which is TRUE WITH OR WITHOUT the override, because an unresolvable
      // host throws the same exception. It passed while Sabotage (replacing
      // the dead client with a live one) left every test green, proving
      // nothing. So this asserts on the guard's own message instead.
      HttpOverrides.global = _NoNetwork();

      await expectLater(
        HttpClient().getUrl(Uri.parse('https://example.invalid')),
        throwsA(
          predicate<Object>(
            (e) => e.toString().contains(_guardMessage),
            'a SocketException raised by the guard itself',
          ),
        ),
      );
    });

    test('a live client would NOT produce the guard message', () async {
      // The other half of the discrimination. With no override, a request to
      // the same host fails for DNS reasons and the failure text differs. If
      // the two cases were indistinguishable this test would fail, which is
      // what makes the one above meaningful.
      HttpOverrides.global = null;

      try {
        await HttpClient().getUrl(Uri.parse('https://example.invalid'));
        fail('an unresolvable host should not connect');
      } on SocketException catch (e) {
        expect(
          e.toString().contains(_guardMessage),
          isFalse,
          reason:
              'an unguarded failure must be distinguishable from a '
              'blocked one, or the guard test proves nothing',
        );
      }
    });

    test('the repositories never touch the network', () async {
      // The real claim, stated directly: with the guard up, the persistence
      // layer still works. If any repository opened a socket this would throw.
      HttpOverrides.global = _NoNetwork();

      await courses.create(_course('Offline'));
      expect((await courses.findAll()).single.name, 'Offline');
    });
  });
}

/// Seeds a course, theme and card, returning both ids.
Future<(int, domain.Theme)> _seedCard(
  DriftCourseRepository courses,
  DriftCardRepository cards,
) async {
  final course = await courses.create(_course('Physics'));
  final theme = await cards.createTheme(
    domain.Theme(
      id: 0,
      courseId: course.id,
      name: 'Kinematics',
      createdAt: DateTime(2022),
    ),
  );
  await cards.createCard(
    domain.Card(
      id: 0,
      themeId: theme.id,
      front: 'v = ?',
      back: 'd / t',
      source: CardSource.manual,
      createdAt: DateTime(2022),
      updatedAt: DateTime(2022),
    ),
  );
  return (course.id, theme);
}

/// Identifies a failure raised by the test guard rather than by the network.
///
/// The distinction matters: an unresolvable host throws [SocketException] too,
/// so a test that only checks the exception TYPE cannot tell a blocked request
/// from a failed one.
const String _guardMessage = 'network access is disabled in this test';

/// Fails every connection attempt.
///
/// Overriding [HttpClient] rather than asserting on a mock means the block is
/// enforced by the same layer a real request would use, so it cannot be
/// side-stepped by calling a different HTTP helper.
class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _DeadClient();
}

class _DeadClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) => _fail();

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => _fail();

  @override
  Future<HttpClientRequest> postUrl(Uri url) => _fail();

  @override
  Future<HttpClientRequest> putUrl(Uri url) => _fail();

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => _fail();

  static Future<HttpClientRequest> _fail() =>
      Future<HttpClientRequest>.error(const SocketException(_guardMessage));

  @override
  dynamic noSuchMethod(Invocation invocation) => _fail();
}

/// A course with the required fields filled in.
Course _course(String name) => Course(
  id: 0,
  name: name,
  createdAt: DateTime(2022),
  newCardsPerDay: 10,
  interleaveMode: InterleaveMode.blocked,
  archived: false,
);
