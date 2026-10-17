/// Shared authoring fixtures for integration-style tests.
///
/// Seeding a course/theme/card trio against a real in-memory Drift database
/// repeats the same bodies in every flow test; keeping them here means a new
/// required entity field is fixed once rather than in each test file.
library;

import 'package:flashcards2/data/repositories/drift_card_repository.dart';
import 'package:flashcards2/data/repositories/drift_course_repository.dart';
import 'package:flashcards2/domain/entities/card.dart' as domain;
import 'package:flashcards2/domain/entities/course.dart';
import 'package:flashcards2/domain/entities/theme.dart' as domain;
import 'package:flashcards2/domain/enums.dart';

Future<Course> seedAuthoringCourse(
  DriftCourseRepository courses,
  String name, {
  bool archived = false,
}) {
  return courses.create(
    Course(
      id: 0,
      name: name,
      createdAt: DateTime(2026),
      newCardsPerDay: 5,
      interleaveMode: InterleaveMode.blocked,
      archived: archived,
    ),
  );
}

Future<domain.Theme> seedAuthoringTheme(
  DriftCardRepository cards,
  Course course,
  String name,
) {
  return cards.createTheme(
    domain.Theme(
      id: 0,
      courseId: course.id,
      name: name,
      createdAt: DateTime(2026),
    ),
  );
}

Future<domain.Card> seedAuthoringCard(
  DriftCardRepository cards,
  domain.Theme theme,
  String front, {
  String back = 'back',
}) {
  return cards.createCard(
    domain.Card(
      id: 0,
      themeId: theme.id,
      front: front,
      back: back,
      source: CardSource.manual,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  );
}
