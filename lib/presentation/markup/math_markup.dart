import 'package:meta/meta.dart';

/// A parsed piece of card text.
@immutable
sealed class CardSegment {
  const new();
}

/// Literal text, including any `$` the author escaped.
@immutable
class TextSegment extends CardSegment {
  const new(this.text);

  final String text;

  @override
  bool operator ==(Object other) => other is TextSegment && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'Text(${text.replaceAll('\n', r'\n')})';
}

/// A LaTeX expression.
@immutable
class LatexSegment extends CardSegment {
  const new(this.latex, {this.display = false});

  final String latex;

  /// True when the author used `$$...$$`, meaning block (centred) layout.
  final bool display;

  @override
  bool operator ==(Object other) =>
      other is LatexSegment && other.latex == latex && other.display == display;

  @override
  int get hashCode => Object.hash(latex, display);

  @override
  String toString() => 'Latex(${display ? 'display' : 'inline'}: $latex)';
}

/// Splits card text into literal and LaTeX runs.
///
/// Rules, chosen so authoring never silently loses text:
///  - `$$...$$` is display math, `$...$` is inline math.
///  - `\$` is a literal dollar sign.
///  - An **unclosed** `$` is not an error: it is emitted as literal text. A
///    learner who types "cost is $5" must see "cost is $5", not a swallowed
///    remainder and not a parse failure.
///  - An empty `$$` pair is literal, because there is nothing to render.
///
/// Deliberately hand-rolled rather than pulled from a Markdown package: the
/// only syntax this app needs is math spans, and a general parser would bring a
/// much wider surface, including constructs that must not be interpreted.
List<CardSegment> parseMathSegments(String source) {
  final segments = <CardSegment>[];
  final buffer = StringBuffer();

  void flushText() {
    if (buffer.isNotEmpty) {
      segments.add(TextSegment(buffer.toString()));
      buffer.clear();
    }
  }

  var i = 0;
  while (i < source.length) {
    final char = source[i];

    if (char == r'\' && i + 1 < source.length && source[i + 1] == r'$') {
      buffer.write(r'$');
      i += 2;
      continue;
    }

    if (char == r'$') {
      final isDisplay = source.startsWith(r'$$', i);
      final delimiter = isDisplay ? r'$$' : r'$';
      final contentStart = i + delimiter.length;
      final end = source.indexOf(delimiter, contentStart);

      if (end != -1 && end > contentStart) {
        flushText();
        segments.add(
          LatexSegment(source.substring(contentStart, end), display: isDisplay),
        );
        i = end + delimiter.length;
        continue;
      }

      // Unclosed, or empty: fall through and treat it as literal text.
    }

    buffer.write(char);
    i++;
  }

  flushText();
  return segments;
}

/// True when [source] contains at least one renderable math span.
bool hasMath(String source) =>
    parseMathSegments(source).any((s) => s is LatexSegment);

/// The plain-text projection, with math left as its LaTeX source.
///
/// Used for search indexing and list previews, where rendering is not possible.
String toPlainText(String source) {
  final buffer = StringBuffer();
  for (final segment in parseMathSegments(source)) {
    switch (segment) {
      case TextSegment(:final text):
        buffer.write(text);
      case LatexSegment(:final latex):
        buffer.write(latex);
    }
  }
  return buffer.toString();
}
