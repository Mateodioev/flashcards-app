/// A themed group of cards inside a course.
class Theme {
  const new({
    required this.id,
    required this.courseId,
    required this.name,
    required this.createdAt,
    this.description,
  });

  final int id;
  final int courseId;
  final String name;
  final String? description;
  final DateTime createdAt;
}
