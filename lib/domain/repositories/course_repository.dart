import 'package:flashcards2/domain/entities/course.dart';

/// Persistence boundary for courses.
///
/// Deliberately framework-free: no Drift and no Flutter types cross this line,
/// which is what keeps the domain layer unit-testable without a widget harness.
abstract interface class CourseRepository {
  Future<Course?> findById(int id);

  Future<List<Course>> findAll({bool includeArchived = false});

  /// Inserts [course] and returns it with its assigned id.
  Future<Course> create(Course course);

  Future<void> update(Course course);

  Future<void> delete(int id);
}
