import 'package:flashcards2/domain/enums.dart';

/// A due card, with just enough context to sequence a session.
class DueEntry {
  const new({
    required this.cardId,
    required this.themeId,
    required this.courseId,
    required this.due,
  });

  final int cardId;
  final int themeId;
  final int courseId;
  final DateTime due;
}

/// Orders due cards into a session queue.
///
/// [InterleaveMode.blocked] keeps each theme together, which suits a learner
/// who is still acquiring a rule. [InterleaveMode.interleaved] round-robins
/// across themes so consecutive cards come from *different* themes — that
/// contrast is the mechanism, not the shuffling itself: it forces the learner
/// to decide which rule applies instead of applying one rule repeatedly.
///
/// Within a theme, earlier-due cards come first in both modes. The ordering is
/// deterministic; no randomness, so a session is reproducible and testable.
List<DueEntry> orderDueCards(
  List<DueEntry> due, {
  required InterleaveMode mode,
  int? limit,
}) {
  final sorted = List<DueEntry>.of(due)
    ..sort((a, b) {
      final byDue = a.due.compareTo(b.due);
      if (byDue != 0) return byDue;
      return a.cardId.compareTo(b.cardId);
    });

  final ordered = switch (mode) {
    InterleaveMode.blocked => _blocked(sorted),
    InterleaveMode.interleaved => _interleaved(sorted),
  };

  if (limit == null || limit >= ordered.length) return ordered;
  return ordered.sublist(0, limit);
}

/// Groups by course, then theme, keeping due order inside each group.
List<DueEntry> _blocked(List<DueEntry> sorted) {
  final ordered = List<DueEntry>.of(sorted)
    ..sort((a, b) {
      final byCourse = a.courseId.compareTo(b.courseId);
      if (byCourse != 0) return byCourse;
      final byTheme = a.themeId.compareTo(b.themeId);
      if (byTheme != 0) return byTheme;
      return a.due.compareTo(b.due);
    });
  return ordered;
}

/// Round-robins across themes, preserving due order within each theme.
///
/// Themes are visited in a stable order (lowest theme id first) so the result
/// does not depend on hash iteration order.
List<DueEntry> _interleaved(List<DueEntry> sorted) {
  final buckets = <int, List<DueEntry>>{};
  for (final entry in sorted) {
    buckets.putIfAbsent(entry.themeId, () => <DueEntry>[]).add(entry);
  }

  final themeIds = buckets.keys.toList()..sort();
  final result = <DueEntry>[];
  var exhausted = false;
  var index = 0;

  while (!exhausted) {
    exhausted = true;
    for (final themeId in themeIds) {
      final bucket = buckets[themeId]!;
      if (index < bucket.length) {
        result.add(bucket[index]);
        exhausted = false;
      }
    }
    index++;
  }
  return result;
}
