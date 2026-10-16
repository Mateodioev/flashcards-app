import 'package:flashcards2/presentation/markup/math_markup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseMathSegments', () {
    test('plain text is one text segment', () {
      expect(parseMathSegments('hello world'), <CardSegment>[
        const TextSegment('hello world'),
      ]);
    });

    test('empty input yields no segments', () {
      expect(parseMathSegments(''), isEmpty);
    });

    test('inline math is extracted', () {
      expect(parseMathSegments(r'a $x^2$ b'), <CardSegment>[
        const TextSegment('a '),
        const LatexSegment('x^2'),
        const TextSegment(' b'),
      ]);
    });

    test('display math is flagged as display', () {
      expect(parseMathSegments(r'$$\frac{a}{b}$$'), <CardSegment>[
        const LatexSegment(r'\frac{a}{b}', display: true),
      ]);
    });

    test('display math is distinguished from two inline spans', () {
      // Without the display flag these two inputs would be identical, and the
      // renderer could not centre the block form.
      final display = parseMathSegments(r'$$x$$');
      final inline = parseMathSegments(r'$x$');
      expect(display, isNot(inline));
      expect((display.single as LatexSegment).display, isTrue);
      expect((inline.single as LatexSegment).display, isFalse);
    });

    test('an escaped dollar is a literal dollar', () {
      expect(parseMathSegments(r'costs \$5'), <CardSegment>[
        const TextSegment(r'costs $5'),
      ]);
    });

    test('an escaped dollar does not open a math span', () {
      final segments = parseMathSegments(r'\$5 and \$10');
      expect(segments, <CardSegment>[const TextSegment(r'$5 and $10')]);
      expect(hasMath(r'\$5 and \$10'), isFalse);
    });

    test('an UNCLOSED dollar stays literal rather than swallowing text', () {
      // The important case: a learner typing a price must not lose the rest of
      // the card, and must not get a parse error.
      const unclosed = r'cost is $5 and a gap';
      expect(parseMathSegments(unclosed), <CardSegment>[
        const TextSegment(unclosed),
      ]);
      expect(toPlainText(unclosed), unclosed);
      expect(hasMath(unclosed), isFalse);
    });

    test('a trailing lone dollar is preserved', () {
      expect(parseMathSegments(r'5$'), <CardSegment>[const TextSegment(r'5$')]);
    });

    test('an empty math span is literal, not an empty render', () {
      expect(parseMathSegments(r'$$'), <CardSegment>[const TextSegment(r'$$')]);
      expect(parseMathSegments(r'$$$$'), <CardSegment>[
        const TextSegment(r'$$$$'),
      ]);
    });

    test('multiple spans in one string', () {
      expect(parseMathSegments(r'$a$ then $b$'), <CardSegment>[
        const LatexSegment('a'),
        const TextSegment(' then '),
        const LatexSegment('b'),
      ]);
    });

    test('math at the very start and end', () {
      expect(parseMathSegments(r'$a$b$c$'), <CardSegment>[
        const LatexSegment('a'),
        const TextSegment('b'),
        const LatexSegment('c'),
      ]);
    });

    test('a backslash inside math is preserved verbatim', () {
      final segments = parseMathSegments(r'$\frac{1}{2}$');
      expect((segments.single as LatexSegment).latex, r'\frac{1}{2}');
    });

    test('newlines survive in text segments', () {
      expect(parseMathSegments('a\nb'), <CardSegment>[
        const TextSegment('a\nb'),
      ]);
    });

    test('parsing is lossless for text and math spans', () {
      const samples = <String>[
        'plain',
        r'$x$',
        r'a $x$ b',
        r'$$\frac{a}{b}$$',
        r'unclosed $ here',
        r'$a$b$c$',
        'multi\nline \$x\$ text',
      ];
      for (final sample in samples) {
        final rebuilt = StringBuffer();
        for (final segment in parseMathSegments(sample)) {
          switch (segment) {
            case TextSegment(:final text):
              rebuilt.write(text);
            case LatexSegment(:final latex, :final display):
              rebuilt.write(display ? '\$\$$latex\$\$' : '\$$latex\$');
          }
        }
        expect(
          rebuilt.toString(),
          sample,
          reason: 'round-trip lost information for: $sample',
        );
      }
    });

    test('escapes are consumed, deliberately, and not round-tripped', () {
      // Documented exception to the losslessness above: `\$` becomes a literal
      // `$`, because the segment holds the resulting text and the escape is a
      // display instruction rather than content. The rendered output is what
      // matters and is correct.
      const escaped = r'costs \$5';
      expect(parseMathSegments(escaped), <CardSegment>[
        const TextSegment(r'costs $5'),
      ]);
    });
  });

  group('hasMath', () {
    test('detects real math', () {
      expect(hasMath(r'$x$'), isTrue);
      expect(hasMath(r'$$\frac{a}{b}$$'), isTrue);
    });

    test('is false for text with escaped or unclosed dollars', () {
      expect(hasMath(r'costs \$5'), isFalse);
      expect(hasMath(r'costs $5'), isFalse);
      expect(hasMath('no math'), isFalse);
    });
  });

  group('toPlainText', () {
    test('keeps latex source so search can match it', () {
      expect(toPlainText(r'see $\alpha$ here'), r'see \alpha here');
    });

    test('is identity for text without math', () {
      expect(toPlainText('just words'), 'just words');
    });
  });
}
