import 'package:drift/drift.dart';
import 'package:flashcards2/data/daos/course_dao.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/domain/entities/course.dart';
import 'package:flashcards2/domain/repositories/course_repository.dart';

/// Drift-backed [CourseRepository].
///
/// The domain entity is the only currency crossing this boundary; Drift rows
/// are mapped to and from it so callers never see a `CourseRow`.
class DriftCourseRepository implements CourseRepository {
  new(AppDatabase db) : _dao = CourseDao(db);

  final CourseDao _dao;

  @override
  Future<Course?> findById(int id) async {
    final row = await _dao.byId(id);
    return row == null ? null : _toDomain(row);
  }

  @override
  Future<List<Course>> findAll({bool includeArchived = false}) async {
    final rows = await _dao.all(includeArchived: includeArchived);
    return rows.map(_toDomain).toList();
  }

  @override
  Future<Course> create(Course course) async {
    final row = await _dao.create(
      CoursesCompanion.insert(
        name: course.name,
        newCardsPerDay: Value(course.newCardsPerDay),
        interleaveMode: Value(course.interleaveMode),
        archived: Value(course.archived),
        createdAt: Value(course.createdAt),
      ),
    );
    return _toDomain(row);
  }

  @override
  Future<void> update(Course course) async {
    await _dao.updateCourse(_toRow(course));
  }

  @override
  Future<void> delete(int id) async {
    await _dao.deleteCourse(id);
  }

  Course _toDomain(CourseRow row) {
    return Course(
      id: row.id,
      name: row.name,
      createdAt: row.createdAt,
      newCardsPerDay: row.newCardsPerDay,
      interleaveMode: row.interleaveMode,
      archived: row.archived,
    );
  }

  CourseRow _toRow(Course course) {
    return CourseRow(
      id: course.id,
      name: course.name,
      createdAt: course.createdAt,
      newCardsPerDay: course.newCardsPerDay,
      interleaveMode: course.interleaveMode,
      archived: course.archived,
    );
  }
}
