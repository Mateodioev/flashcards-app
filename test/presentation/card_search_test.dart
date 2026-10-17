import 'package:flashcards2/domain/entities/card.dart';
import 'package:flashcards2/domain/entities/card_search.dart';
import 'package:flashcards2/domain/entities/theme.dart';
import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/presentation/search/card_search.dart';
import 'package:flutter_test/flutter_test.dart';

/// Matching semantics for the global card search (T5.7, S2).
///
/// The search reads the plain-text projection — math contributes its LaTeX
/// source, and the `$` delimiters never split a phrase that spans a math
/// span. These are pure-function tests: no database and no widgets.
void main() {
  ScopedCard scoped({required String front, required String back}) {
    return ScopedCard(
      card: Card(
        id: 1,
        themeId: 1,
        front: front,
        back: back,
        source: CardSource.manual,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
      theme: Theme(
        id: 1,
        courseId: 1,
        name: 'Theme',
        createdAt: DateTime(2026),
      ),
      courseName: 'Course',
    );
  }

  group('cardsMatchingQuery', () {
    test('a blank or whitespace-only query matches nothing', () {
      final candidates = [scoped(front: 'anything', back: 'else')];
      expect(cardsMatchingQuery('', candidates), isEmpty);
      expect(cardsMatchingQuery('   ', candidates), isEmpty);
    });

    test('matches case-insensitively on the front', () {
      final candidates = [scoped(front: 'FRACTION of a whole', back: 'x')];
      expect(cardsMatchingQuery('fraction', candidates), hasLength(1));
    });

    test('matches case-insensitively with accented characters', () {
      final candidates = [scoped(front: 'El Ángulo recto', back: 'x')];
      expect(cardsMatchingQuery('ángulo', candidates), hasLength(1));
    });

    test('a phrase spanning a math span still matches', () {
      final candidates = [scoped(front: r'sum of $x^2$ total', back: 'x')];
      expect(cardsMatchingQuery('sum of x^2 total', candidates), hasLength(1));
    });

    test('matches inside a math span by its LaTeX source', () {
      final candidates = [scoped(front: r'Compute $\frac{1}{2}$', back: 'x')];
      expect(cardsMatchingQuery('frac', candidates), hasLength(1));
    });

    test('matches on the back when the front does not contain the query', () {
      final candidates = [scoped(front: 'question', back: 'the answer')];
      expect(cardsMatchingQuery('answer', candidates), hasLength(1));
    });

    test('excludes cards that contain the query on neither side', () {
      final candidates = [scoped(front: 'apples', back: 'oranges')];
      expect(cardsMatchingQuery('pear', candidates), isEmpty);
    });

    test('leading and trailing whitespace in the query is ignored', () {
      final candidates = [scoped(front: 'green light', back: 'x')];
      expect(cardsMatchingQuery('  green  ', candidates), hasLength(1));
    });
  });
}
