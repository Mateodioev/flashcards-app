import 'package:flashcards2/domain/enums.dart';

/// A course: a named collection of themes, and the unit a learner studies.
class Course {
  const new({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.newCardsPerDay,
    required this.interleaveMode,
    required this.archived,
  });

  final int id;
  final String name;
  final DateTime createdAt;

  /// Per-course intake cap, copied from onboarding but overridable.
  final int newCardsPerDay;

  /// Assigned by the prior-knowledge probe.
  final InterleaveMode interleaveMode;

  final bool archived;
}
