import 'package:flashcards2/domain/entities/card_search.dart';
import 'package:flashcards2/presentation/markup/math_markup.dart';

/// True when [query] carries nothing searchable: empty or whitespace only.
///
/// The single owner of the blank rule. The matcher, the provider's
/// short-circuit and the screen's idle state all read this, so the rule
/// cannot drift apart in three places.
bool isBlankQuery(String query) => query.trim().isEmpty;

/// Filters [candidates] down to the cards matching [query].
///
/// Matching reads the plain-text projection of both sides of the card (see
/// [toPlainText]): math contributes its LaTeX source, and the `$` delimiters
/// never split a phrase that spans a math span — "sum of x^2 total" finds a
/// card storing `sum of $x^2$ total`. Matching is case-insensitive via
/// `toLowerCase`, which folds Unicode where SQL `LIKE` would fold ASCII only.
///
/// A blank or whitespace-only query matches nothing and never turns the
/// search into "list every card": the search screen is a lookup, not a
/// browsing surface.
List<ScopedCard> cardsMatchingQuery(
  String query,
  List<ScopedCard> candidates,
) {
  if (isBlankQuery(query)) return const [];
  final normalized = query.trim().toLowerCase();

  bool matches(String source) =>
      toPlainText(source).toLowerCase().contains(normalized);

  return [
    for (final candidate in candidates)
      if (matches(candidate.card.front) || matches(candidate.card.back))
        candidate,
  ];
}
