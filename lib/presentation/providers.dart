import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/data/repositories/drift_card_repository.dart';
import 'package:flashcards2/data/repositories/drift_course_repository.dart';
import 'package:flashcards2/data/repositories/drift_review_log_repository.dart';
import 'package:flashcards2/data/repositories/drift_settings_repository.dart';
import 'package:flashcards2/domain/entities/card.dart';
import 'package:flashcards2/domain/entities/course.dart';
import 'package:flashcards2/domain/entities/theme.dart';
import 'package:flashcards2/domain/repositories/card_repository.dart';
import 'package:flashcards2/domain/repositories/course_repository.dart';
import 'package:flashcards2/domain/repositories/review_log_repository.dart';
import 'package:flashcards2/domain/repositories/settings_repository.dart';
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
