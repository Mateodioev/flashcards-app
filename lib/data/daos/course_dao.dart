import 'package:drift/drift.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/data/tables/tables.dart';

part 'course_dao.g.dart';

/// Create/read/update/delete for courses.
@DriftAccessor(tables: [Courses])
class CourseDao extends DatabaseAccessor<AppDatabase> with _$CourseDaoMixin {
  new(super.attachedDatabase);

  Future<List<CourseRow>> all({bool includeArchived = false}) {
    final query = select(courses);
    if (!includeArchived) {
      query.where((t) => t.archived.equals(false));
    }
    return query.get();
  }

  Stream<List<CourseRow>> watchAll({bool includeArchived = false}) {
    final query = select(courses);
    if (!includeArchived) {
      query.where((t) => t.archived.equals(false));
    }
    return query.watch();
  }

  Future<CourseRow?> byId(int id) {
    return (select(courses)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<CourseRow> create(CoursesCompanion course) {
    return into(courses).insertReturning(course);
  }

  Future<bool> updateCourse(CourseRow course) {
    return update(courses).replace(course);
  }

  Future<int> deleteCourse(int id) {
    return (delete(courses)..where((t) => t.id.equals(id))).go();
  }
}
