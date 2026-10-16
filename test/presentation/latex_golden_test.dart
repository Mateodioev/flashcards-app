import 'package:flashcards2/core/theme.dart';
import 'package:flashcards2/presentation/widgets/card_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Golden tests for math rendering in both modes.
///
/// These exist because the interesting failure is invisible to unit tests:
/// `parseMathSegments` can return exactly the right segment while the formula
/// itself lays out to nothing, overflows its box, or paints in a colour that
/// disappears against a dark surface. Only a rendered frame catches that.
///
/// **What these do and do not prove.** Flutter's test environment substitutes
/// the Ahem font, in which every glyph is a filled rectangle, and
/// `flutter_math_fork` resolves its KaTeX faces through an asset path the test
/// binding does not honour — registering them by hand was measured to make no
/// difference at all (byte-identical output with and without the load), so that
/// workaround was removed rather than left in as dead code.
///
/// The result is that these goldens verify **layout and colour**, not
/// letterforms: that a formula occupies real space instead of collapsing, that
/// a fraction stacks rather than rendering inline, that display math breaks
/// onto its own line, and that an unrenderable formula paints a visible error
/// rather than a blank card. Verifying the actual glyph shapes needs a real
/// device screenshot, which is an integration test, not a unit one. Read the
/// images once when they change; do not treat a passing golden as proof the
/// maths looks right.
///
/// Regenerate after an intentional visual change:
///   flutter test --update-goldens test/presentation/latex_golden_test.dart
void main() {
  /// Wraps [child] in the real app theme, because a golden taken against a
  /// default `MaterialApp` would not represent what the learner sees.
  Widget frame(Widget child, Brightness brightness) {
    final theme = brightness == Brightness.dark
        ? AppTheme.dark
        : AppTheme.light;
    return MaterialApp(
      theme: theme,
      home: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Center(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );
  }

  Future<void> expectGolden(
    WidgetTester tester,
    String description,
    String source,
  ) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        frame(
          CardContent(source, textStyle: const TextStyle(fontSize: 20)),
          brightness,
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(CardContent),
        matchesGoldenFile('goldens/${description}_${brightness.name}.png'),
      );
    }
  }

  group('math rendering goldens', () {
    testWidgets('inline fraction', (tester) async {
      await expectGolden(tester, 'inline_fraction', r'What is $\frac{1}{2}$?');
    });

    testWidgets('display math on its own line', (tester) async {
      await expectGolden(
        tester,
        'display_math',
        r'The identity: $$\int_0^1 x^2 \, dx$$',
      );
    });

    testWidgets('mixed text and several formulas', (tester) async {
      await expectGolden(
        tester,
        'mixed_segments',
        r'Given $\alpha$ and $\beta$, solve $x^2 + y^2 = z^2$ for $z$.',
      );
    });

    testWidgets('a formula the parser cannot render', (tester) async {
      // The failure path is a first-class visual state: an unrenderable span
      // must still show something readable rather than a blank card.
      await expectGolden(tester, 'malformed_formula', r'Broken: $\frac{1}{$');
    });

    testWidgets('plain text with no math', (tester) async {
      await expectGolden(tester, 'plain_text', 'No math here at all.');
    });
  });
}
