import 'package:flashcards2/data/ai/openai_compatible_client.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/data/repositories/drift_card_repository.dart';
import 'package:flashcards2/data/repositories/drift_course_repository.dart';
import 'package:flashcards2/data/repositories/drift_reminder_repository.dart';
import 'package:flashcards2/data/repositories/drift_review_log_repository.dart';
import 'package:flashcards2/data/repositories/drift_settings_repository.dart';
import 'package:flashcards2/domain/ai/ai_settings_service.dart';
import 'package:flashcards2/domain/entities/card.dart';
import 'package:flashcards2/domain/entities/card_search.dart';
import 'package:flashcards2/domain/entities/course.dart';
import 'package:flashcards2/domain/entities/scheduling.dart';
import 'package:flashcards2/domain/entities/theme.dart';
import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/domain/onboarding/onboarding_service.dart';
import 'package:flashcards2/domain/reminders/reminder_repository.dart';
import 'package:flashcards2/domain/repositories/card_repository.dart';
import 'package:flashcards2/domain/repositories/course_repository.dart';
import 'package:flashcards2/domain/repositories/review_log_repository.dart';
import 'package:flashcards2/domain/repositories/settings_repository.dart';
import 'package:flashcards2/presentation/search/card_search.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'providers.g.dart';

/// The application database.
///
/// Overridden in `main` with the on-disk database, and in tests with an
/// in-memory one — so nothing below this line needs to know which it has.
@Riverpod(keepAlive: true)
AppDatabase database(Ref ref) {
  throw UnimplementedError(
    'databaseProvider must be overridden. See main.dart.',
  );
}

@Riverpod(keepAlive: true)
CourseRepository courseRepository(Ref ref) {
  return DriftCourseRepository(ref.watch(databaseProvider));
}

@Riverpod(keepAlive: true)
CardRepository cardRepository(Ref ref) {
  return DriftCardRepository(ref.watch(databaseProvider));
}

@Riverpod(keepAlive: true)
ReviewLogRepository reviewLogRepository(Ref ref) {
  return DriftReviewLogRepository(ref.watch(databaseProvider));
}

@Riverpod(keepAlive: true)
SettingsRepository settingsRepository(Ref ref) {
  return DriftSettingsRepository(ref.watch(databaseProvider));
}

@Riverpod(keepAlive: true)
ReminderRepository reminderRepository(Ref ref) {
  return DriftReminderRepository(ref.watch(databaseProvider));
}

/// Non-archived courses.
///
/// Invalidate after any create, edit or delete so the list rebuilds from the
/// database rather than from a hand-maintained cache.
@riverpod
Future<List<Course>> courses(Ref ref) {
  return ref.watch(courseRepositoryProvider).findAll();
}

/// Themes within one course.
@riverpod
Future<List<Theme>> themes(Ref ref, int courseId) {
  return ref.watch(cardRepositoryProvider).findThemesByCourse(courseId);
}

/// Cards within one theme.
@riverpod
Future<List<Card>> cards(Ref ref, int themeId) {
  return ref.watch(cardRepositoryProvider).findCardsByTheme(themeId);
}

/// One card by id, for the review screen.
///
/// The session walks cards by id rather than holding whole entities, so a card
/// edited mid-session is not shown from a stale in-memory copy.
@riverpod
Future<Card?> cardById(Ref ref, int cardId) {
  return ref.watch(cardRepositoryProvider).findCardById(cardId);
}

/// One global card-search lookup: the free text plus an optional scope.
///
/// A record, so family caching compares by value — the search screen rebuilds
/// the query with each keystroke and a repeated keystroke still hits the
/// provider cache instead of re-running the query.
typedef CardSearchQuery = ({String text, int? courseId, int? themeId});

/// Cards matching a [CardSearchQuery], ordered by course, theme and card id.
///
/// Scoping and archived-course exclusion live in the repository; matching
/// semantics live in `cardsMatchingQuery`. A blank query returns nothing, so
/// the provider never becomes a "list every card" back door.
@riverpod
Future<List<ScopedCard>> cardSearchResults(Ref ref, CardSearchQuery query) {
  // Short-circuit to avoid a wasted repository round-trip; the authoritative
  // semantics still live in `cardsMatchingQuery`.
  if (isBlankQuery(query.text)) {
    return Future.value(const <ScopedCard>[]);
  }
  return ref
      .watch(cardRepositoryProvider)
      .findCardsWithContext(courseId: query.courseId, themeId: query.themeId)
      .then((candidates) => cardsMatchingQuery(query.text, candidates));
}

/// Persists onboarding outcomes into the settings row.
@Riverpod(keepAlive: true)
OnboardingService onboardingService(Ref ref) {
  return OnboardingService(ref.watch(settingsRepositoryProvider));
}

/// The API key store. Overridden in tests with an in-memory implementation so
/// no test touches the platform keystore.
@Riverpod(keepAlive: true)
ApiKeyStore apiKeyStore(Ref ref) => SecureApiKeyStore();

/// Reads and writes the AI configuration.
@Riverpod(keepAlive: true)
AiSettingsService aiSettingsService(Ref ref) {
  return AiSettingsService(
    ref.watch(settingsRepositoryProvider),
    ref.watch(apiKeyStoreProvider),
  );
}

/// The persisted settings row.
///
/// Invalidate after writing preferences so the app re-reads rather than keeping
/// a second copy in memory.
@Riverpod(keepAlive: true)
Future<AppSettings> appSettings(Ref ref) {
  return ref.watch(settingsRepositoryProvider).read();
}

/// The active theme mode.
///
/// Falls back to [ThemeMode.system] while settings are loading, which is the
/// correct default: it matches the device rather than flashing a preference the
/// learner never chose.
@Riverpod(keepAlive: true)
ThemeMode themeMode(Ref ref) {
  final settings = ref.watch(appSettingsProvider);
  return settings.maybeWhen(
    data: (value) => switch (value.themeMode) {
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
      AppThemeMode.system => ThemeMode.system,
    },
    orElse: () => ThemeMode.system,
  );
}
