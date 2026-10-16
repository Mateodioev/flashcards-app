import 'dart:convert';

import 'package:flashcards2/domain/ai/flashcard_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parse — the happy path', () {
    test('reads a clean response', () {
      final result = FlashcardPrompt.parse(
        '{"cards":[{"front":"Q1","back":"A1"},{"front":"Q2","back":"A2"}]}',
      );
      expect(result.drafts, <CardDraft>[
        const CardDraft(front: 'Q1', back: 'A1'),
        const CardDraft(front: 'Q2', back: 'A2'),
      ]);
      expect(result.dropped, 0);
      expect(result.error, isNull);
    });

    test('an empty array is a valid answer, not an error', () {
      final result = FlashcardPrompt.parse('{"cards":[]}');
      expect(result.drafts, isEmpty);
      expect(result.dropped, 0);
      expect(
        result.error,
        contains('nothing worth memorising'),
        reason: 'an empty result is legitimate and should say so plainly',
      );
    });

    test('preserves LaTeX verbatim when properly escaped', () {
      // Built with jsonEncode so the escaping under test is the only escaping:
      // a model that correctly doubled its backslashes.
      final body = jsonEncode({
        'cards': [
          {'front': r'Solve $\frac{1}{2}$', 'back': r'$0.5$'},
        ],
      });
      final result = FlashcardPrompt.parse(body);

      expect(result.drafts.single.front, r'Solve $\frac{1}{2}$');
      expect(result.drafts.single.back, r'$0.5$');
    });

    test('repairs LaTeX a model left unescaped', () {
      // The realistic failure: the model obeyed "preserve LaTeX exactly" and
      // emitted a bare backslash. Left alone, \frac decodes to a form feed
      // followed by "rac".
      const body =
          r'{"cards":[{"front":"Solve $\frac{1}{2}$","back":"$0.5$"}]}';
      final result = FlashcardPrompt.parse(body);

      expect(
        result.drafts.single.front,
        r'Solve $\frac{1}{2}$',
        reason: 'a bare backslash-f must survive as LaTeX, not a control char',
      );
    });

    test('repairs every command whose name collides with a JSON escape', () {
      // \f \t \b \n \r \u are JSON escapes; each of these would otherwise
      // decode to a control character or, for \u, break the document entirely.
      const commands = <String>[
        'frac',
        'forall',
        'times',
        'theta',
        'beta',
        'nu',
        'rho',
        'underline',
        'rightarrow',
        'uparrow',
        'because',
      ];
      for (final name in commands) {
        final latex = '\\$name';
        final body = '{"cards":[{"front":"\$$latex\$","back":"A"}]}';
        final result = FlashcardPrompt.parse(body);
        expect(
          result.drafts.single.front,
          '\$$latex\$',
          reason: 'failed to repair \\$name',
        );
      }
    });

    test('does not corrupt a genuine JSON escape', () {
      // A real newline the model intended, not a LaTeX command.
      final body = jsonEncode({
        'cards': [
          {'front': 'line one\nline two', 'back': 'A'},
        ],
      });
      final result = FlashcardPrompt.parse(body);
      expect(result.drafts.single.front, 'line one\nline two');
    });
  });

  group('parse — tolerating real model output', () {
    test('unwraps a Markdown code fence', () {
      final result = FlashcardPrompt.parse(
        '```json\n{"cards":[{"front":"Q","back":"A"}]}\n```',
      );
      expect(result.drafts, hasLength(1));
      expect(result.error, isNull);
    });

    test('unwraps a fence with no language tag', () {
      final result = FlashcardPrompt.parse(
        '```\n{"cards":[{"front":"Q","back":"A"}]}\n```',
      );
      expect(result.drafts, hasLength(1));
    });

    test('ignores prose before the JSON', () {
      final result = FlashcardPrompt.parse(
        'Sure! Here are the cards:\n{"cards":[{"front":"Q","back":"A"}]}',
      );
      expect(result.drafts, hasLength(1));
    });

    test('ignores prose after the JSON', () {
      final result = FlashcardPrompt.parse(
        '{"cards":[{"front":"Q","back":"A"}]}\n\nLet me know if you want more!',
      );
      expect(result.drafts, hasLength(1));
    });

    test('prose containing a brace does not corrupt the slice', () {
      // The naive "first { to last }" approach fails here; the balanced scan
      // must not.
      final result = FlashcardPrompt.parse(
        'Here { is } some { noise }\n{"cards":[{"front":"Q","back":"A"}]}',
      );
      expect(result.drafts, hasLength(1));
      expect(result.drafts.single.front, 'Q');
    });

    test('a brace inside a string value does not end the object early', () {
      final result = FlashcardPrompt.parse(
        '{"cards":[{"front":"What is {x}?","back":"A set"}]}',
      );
      expect(result.drafts.single.front, 'What is {x}?');
    });

    test('an escaped quote inside a string survives', () {
      final result = FlashcardPrompt.parse(
        r'{"cards":[{"front":"He said \"hi\"","back":"A"}]}',
      );
      expect(result.drafts.single.front, 'He said "hi"');
    });
  });

  group('parse — partial failure', () {
    test('one malformed entry costs one card, not the batch', () {
      final result = FlashcardPrompt.parse(
        '{"cards":['
        '{"front":"Q1","back":"A1"},'
        '{"front":123,"back":"A2"},'
        '{"front":"Q3","back":"A3"}]}',
      );
      expect(result.drafts, hasLength(2));
      expect(result.dropped, 1);
      expect(
        result.error,
        isNull,
        reason: 'the batch succeeded even though one entry did not',
      );
    });

    test('an entry missing a field is dropped and counted', () {
      final result = FlashcardPrompt.parse(
        '{"cards":[{"front":"Q"},{"front":"Q2","back":"A2"}]}',
      );
      expect(result.drafts, hasLength(1));
      expect(result.dropped, 1);
    });

    test('an entry with an empty side is dropped', () {
      final result = FlashcardPrompt.parse(
        '{"cards":[{"front":"   ","back":"A"}, '
        '{"front":"Q2","back":"A2"}]}',
      );
      expect(result.drafts, hasLength(1));
      expect(result.dropped, 1);
    });

    test('a non-object entry is dropped rather than throwing', () {
      final result = FlashcardPrompt.parse(
        '{"cards":["nonsense",42,null,{"front":"Q","back":"A"}]}',
      );
      expect(result.drafts, hasLength(1));
      expect(result.dropped, 3);
    });

    test('all entries bad reports the count', () {
      final result = FlashcardPrompt.parse(
        '{"cards":[{"front":"Q"},{"back":"A"}]}',
      );
      expect(result.drafts, isEmpty);
      expect(result.dropped, 2);
      expect(result.error, contains('2 unusable'));
    });
  });

  group('parse — hard failures', () {
    test('a non-JSON body is reported, not thrown', () {
      final result = FlashcardPrompt.parse('I cannot help with that.');
      expect(result.drafts, isEmpty);
      expect(result.error, isNotNull);
    });

    test('a truncated object is reported', () {
      final result = FlashcardPrompt.parse('{"cards":[{"front":"Q","back"');
      expect(result.drafts, isEmpty);
      expect(result.error, isNotNull);
    });

    test('a JSON array instead of an object is reported', () {
      final result = FlashcardPrompt.parse('[{"front":"Q","back":"A"}]');
      expect(result.drafts, isEmpty);
      expect(result.error, isNotNull);
    });

    test('a missing cards key is reported', () {
      final result = FlashcardPrompt.parse('{"flashcards":[]}');
      expect(result.drafts, isEmpty);
      expect(result.error, contains('cards'));
    });

    test('an empty body is reported', () {
      final result = FlashcardPrompt.parse('');
      expect(result.drafts, isEmpty);
      expect(result.error, isNotNull);
    });

    test('parse never throws, whatever it is handed', () {
      const inputs = <String>[
        '',
        '   ',
        '{',
        '}',
        '{}',
        'null',
        '"a string"',
        '{"cards":"not a list"}',
        '{"cards":null}',
        '{"cards":[{"front":null,"back":null}]}',
      ];
      for (final input in inputs) {
        expect(
          () => FlashcardPrompt.parse(input),
          returnsNormally,
          reason: 'threw on input: $input',
        );
      }
    });
  });
}
