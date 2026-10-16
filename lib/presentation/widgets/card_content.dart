import 'package:flashcards2/presentation/markup/math_markup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// Renders card text, turning `$...$` and `$$...$$` spans into real math.
///
/// A malformed expression renders a readable inline error instead of throwing
/// or blanking the card. That matters because card text is authored by hand and
/// by a model: one bad backslash must never cost the learner the whole card.
class CardContent extends StatelessWidget {
  const new(
    this.source, {
    super.key,
    this.textStyle,
    this.textAlign = TextAlign.start,
  });

  final String source;
  final TextStyle? textStyle;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = textStyle ?? DefaultTextStyle.of(context).style;
    final segments = parseMathSegments(source);

    if (segments.every((s) => s is TextSegment)) {
      // No math: a plain Text avoids the per-segment layout overhead and keeps
      // selection behaviour ordinary.
      return Text(source, style: effectiveStyle, textAlign: textAlign);
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: _wrapAlignmentFor(textAlign),
      children: <Widget>[
        for (final segment in segments)
          switch (segment) {
            TextSegment(:final text) => Text(
              text,
              style: effectiveStyle,
              textAlign: textAlign,
            ),
            LatexSegment(:final latex, :final display) => _Latex(
              latex: latex,
              display: display,
              style: effectiveStyle,
            ),
          },
      ],
    );
  }

  static WrapAlignment _wrapAlignmentFor(TextAlign align) {
    return switch (align) {
      TextAlign.center => WrapAlignment.center,
      TextAlign.end => WrapAlignment.end,
      TextAlign.justify => WrapAlignment.spaceBetween,
      _ => WrapAlignment.start,
    };
  }
}

class _Latex extends StatelessWidget {
  const new({required this.latex, required this.display, required this.style});

  final String latex;
  final bool display;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final widget = Math.tex(
      latex,
      mathStyle: display ? MathStyle.display : MathStyle.text,
      textStyle: style.copyWith(fontSize: (style.fontSize ?? 16) * _scale),
      onErrorFallback: (error) => _LatexError(latex: latex, style: style),
    );

    if (!display) return widget;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: widget,
    );
  }

  /// Display math is set slightly larger, as it carries the card's meaning when
  /// it is on its own line.
  static const double _scale = 1.15;
}

/// Shown in place of an expression that will not parse.
///
/// Displays the raw LaTeX so the author can see and fix what they typed, rather
/// than being told only that something is wrong.
class _LatexError extends StatelessWidget {
  const new({required this.latex, required this.style});

  final String latex;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Malformed math expression',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, size: 14, color: scheme.onErrorContainer),
            const SizedBox(width: 4),
            Text(
              latex,
              style: style.copyWith(
                color: scheme.onErrorContainer,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
