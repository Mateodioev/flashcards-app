import 'package:drift/drift.dart';
import 'package:flashcards2/domain/enums.dart';

/// Maps [ReviewState] to and from the review-state vocabulary stored in
/// SQLite: `new`, `learning`, `review`, `relearning`.
///
/// Drift's `textEnum` cannot be used here. It generates an `EnumNameConverter`
/// that round-trips through the enum member's Dart identifier, and `new` is a
/// reserved word in Dart, so no enum member can be named `new`. A hand-written
/// converter is the idiomatic escape hatch: it stores the vocabulary the design
/// specifies instead of leaking the `new_` Dart workaround into the database.
///
/// The reverse lookup is an explicit switch rather than `values.byName` for the
/// same reason — `byName` matches identifiers, not storage values.
class ReviewStateConverter extends TypeConverter<ReviewState, String> {
  const new();

  @override
  ReviewState fromSql(String fromDb) {
    return switch (fromDb) {
      'new' => ReviewState.new_,
      'learning' => ReviewState.learning,
      'review' => ReviewState.review,
      'relearning' => ReviewState.relearning,
      _ => throw ArgumentError.value(
        fromDb,
        'fromDb',
        'Unknown review state; expected new/learning/review/relearning',
      ),
    };
  }

  @override
  String toSql(ReviewState value) {
    return switch (value) {
      ReviewState.new_ => 'new',
      ReviewState.learning => 'learning',
      ReviewState.review => 'review',
      ReviewState.relearning => 'relearning',
    };
  }
}
