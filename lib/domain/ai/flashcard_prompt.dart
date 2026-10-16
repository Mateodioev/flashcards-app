import 'dart:convert';

import 'package:meta/meta.dart';

/// One flashcard as proposed by a model, before human review.
@immutable
class CardDraft {
  const new({required this.front, required this.back});

  final String front;
  final String back;

  @override
  bool operator ==(Object other) =>
      other is CardDraft && other.front == front && other.back == back;

  @override
  int get hashCode => Object.hash(front, back);

  @override
  String toString() => 'CardDraft($front / $back)';
}

/// The outcome of parsing a model response.
class DraftParseResult {
  const new({required this.drafts, this.dropped = 0, this.error});

  /// Cards that parsed cleanly and are worth showing for review.
  final List<CardDraft> drafts;

  /// Entries that were present but unusable.
  ///
  /// Counted rather than silently ignored: a model that returns five cards of
  /// which three are malformed is a prompt problem the author should see.
  final int dropped;

  /// Set when nothing usable came back. Null when [drafts] is non-empty.
  final String? error;

  bool get hasDrafts => drafts.isNotEmpty;
}

/// Builds the instruction sent to the model.
///
/// The prompt asks for a strict JSON object and nothing else. Every model on
/// the target provider advertises structured outputs, but this app cannot rely
/// on that for arbitrary OpenAI-compatible endpoints, so the parser tolerates
/// prose and code fences around the payload rather than demanding a clean body.
abstract final class FlashcardPrompt {
  /// The system instruction.
  ///
  /// Kept deliberately narrow: the model's job is transcription and
  /// atomisation, not teaching. Cards that editorialise or add facts not in the
  /// image are worse than useless, because they enter a spaced-repetition
  /// schedule and get memorised as if correct.
  static const String system = '''
You convert study material into atomic flashcards.

Rules:
- Extract only what is present in the provided material. Never add facts,
  examples, or context that is not there.
- One idea per card. If a line contains two facts, produce two cards.
- The front is a question or prompt with a single unambiguous answer.
  The back is that answer.
- Preserve any LaTeX exactly as written, including its delimiters.
- Preserve the source's language. Do not translate.
- Prefer concrete, testable prompts. "What is X?" beats "Explain X."
- If the material contains nothing worth memorising, return an empty array.

Respond with JSON only, no prose and no code fences, in exactly this shape:
{"cards":[{"front":"...","back":"..."}]}''';

  /// The user turn accompanying an image.
  static const String imageInstruction =
      'Convert this material into flashcards following the rules.';

  /// Extracts draft cards from a model response body.
  ///
  /// Tolerates real failure modes rather than failing whole:
  ///  - the payload wrapped in a Markdown code fence
  ///  - prose before or after the JSON object, including prose with braces
  ///  - **unescaped LaTeX backslashes** (see [_repairLatexEscapes])
  ///  - individual entries that are malformed while others are fine
  ///
  /// A single bad entry costs one card, not the whole batch — losing five good
  /// cards because the sixth was malformed would be an unreasonable trade.
  static DraftParseResult parse(String body) {
    final candidates = _balancedObjects(body);
    if (candidates.isEmpty) {
      return const DraftParseResult(
        drafts: <CardDraft>[],
        error: 'The response did not contain a JSON object.',
      );
    }

    // Repair runs BEFORE decoding, and before the candidate is chosen. Most of
    // the damage is silent: \f, \t, \b, \n and \r are all valid JSON escapes,
    // so an unescaped \frac decodes without error into a form feed followed by
    // "rac". Only \u actually throws, which is why ordering matters — a
    // decodability check on the raw text would reject a body that is perfectly
    // recoverable.
    Map<String, Object?>? payload;
    var sawAnyObject = false;

    for (final candidate in candidates) {
      final Object? decoded;
      try {
        decoded = jsonDecode(_repairLatexEscapes(candidate));
      } on FormatException {
        continue;
      }
      if (decoded is! Map<String, Object?>) continue;

      sawAnyObject = true;
      if (decoded['cards'] is List) {
        payload = decoded;
        break;
      }
    }

    if (payload == null) {
      return DraftParseResult(
        drafts: const <CardDraft>[],
        error: sawAnyObject
            ? 'The response had no "cards" array.'
            : 'The response was not valid JSON.',
      );
    }

    final drafts = <CardDraft>[];
    var dropped = 0;

    for (final entry in payload['cards']! as List) {
      final card = _asDraft(entry);
      if (card == null) {
        dropped++;
      } else {
        drafts.add(card);
      }
    }

    if (drafts.isEmpty) {
      return DraftParseResult(
        drafts: const <CardDraft>[],
        dropped: dropped,
        error: dropped == 0
            ? 'The model returned no cards. The material may have had nothing '
                  'worth memorising.'
            : 'The model returned $dropped unusable '
                  '${dropped == 1 ? 'entry' : 'entries'}.',
      );
    }

    return DraftParseResult(drafts: drafts, dropped: dropped);
  }

  /// LaTeX commands whose names collide with JSON string escapes.
  ///
  /// In JSON, `\` followed by `n`, `t`, `b`, or `f` is a control character, so
  /// an unescaped `\frac` decodes to a form feed followed by `rac`, `\times` to
  /// a tab, `\beta` to a backspace. `\u` is worse still: it demands four hex
  /// digits and makes the whole document invalid.
  ///
  /// Repair is deliberately driven by this **known-command list** rather than a
  /// heuristic, because the case is genuinely ambiguous: `\nu` could be the
  /// command, or a newline followed by the letter `u`. Guessing would corrupt
  /// legitimate text, so only recognised commands are rewritten.
  static const List<String> _latexCommands = <String>[
    'frac',
    'forall',
    'frown',
    'times',
    'theta',
    'tau',
    'tan',
    'tanh',
    'text',
    'textbf',
    'textit',
    'texttt',
    'to',
    'top',
    'triangle',
    'therefore',
    'beta',
    'big',
    'bigcap',
    'bigcup',
    'bigoplus',
    'bigotimes',
    'bmod',
    'binom',
    'bullet',
    'because',
    'nu',
    'nabla',
    'neq',
    'newline',
    'nolimits',
    'nonumber',
    'notin',
    'normal',
    'nexists',
    'nmid',
    'rho',
    'right',
    'rightarrow',
    'rangle',
    'rceil',
    'rfloor',
    'rtimes',
    'uarr',
    'uparrow',
    'underline',
    'underbrace',
    'upsilon',
    'uplus',
  ];

  /// Doubles the backslash of any recognised LaTeX command that a model left
  /// unescaped, leaving genuine JSON escapes untouched.
  static String _repairLatexEscapes(String source) {
    final buffer = StringBuffer();
    var i = 0;
    while (i < source.length) {
      final char = source[i];
      if (char != r'\' || i + 1 >= source.length) {
        buffer.write(char);
        i++;
        continue;
      }

      // An already-escaped pair is copied untouched. Without this, the scan
      // consumes the first backslash of `\\frac` and then "repairs" the second,
      // producing three backslashes and a control character.
      if (source[i + 1] == r'\') {
        buffer.write(r'\\');
        i += 2;
        continue;
      }

      final rest = source.substring(i + 1);
      final match = _latexCommands.firstWhere(
        rest.startsWith,
        orElse: () => '',
      );

      if (match.isEmpty) {
        buffer.write(char);
        i++;
        continue;
      }

      // `\frac` -> `\\frac`, so JSON decoding yields the backslash the LaTeX
      // needs.
      //
      // NOT a raw string: interpolating `$match` is the point. In a raw string
      // this writes the literal characters `$match`.
      buffer.write('\\\\$match');
      i += match.length + 1;
    }
    return buffer.toString();
  }

  static CardDraft? _asDraft(Object? entry) {
    if (entry is! Map) return null;
    final front = entry['front'];
    final back = entry['back'];
    if (front is! String || back is! String) return null;

    final trimmedFront = front.trim();
    final trimmedBack = back.trim();
    // An empty side is not a usable card, however well-formed the JSON is.
    if (trimmedFront.isEmpty || trimmedBack.isEmpty) return null;

    return CardDraft(front: trimmedFront, back: trimmedBack);
  }

  /// Finds the JSON object in [body], ignoring anything around it.
  ///
  /// Tries **every** balanced top-level object rather than only the first.
  /// Prose often contains braces of its own ("{ see above }"), and taking the
  /// first balanced slice would hand the decoder that prose and lose the real
  /// payload.
  ///
  /// Returns candidates without judging them: decodability is decided by the
  /// caller, *after* LaTeX repair, because an unescaped `\underline` makes a
  /// body undecodable until it has been repaired.
  static List<String> _balancedObjects(String body) {
    final objects = <String>[];

    for (
      var start = body.indexOf('{');
      start != -1;
      start = body.indexOf('{', start + 1)
    ) {
      var depth = 0;
      var inString = false;
      var escaped = false;

      for (var i = start; i < body.length; i++) {
        final char = body[i];
        if (inString) {
          if (escaped) {
            escaped = false;
          } else if (char == r'\') {
            escaped = true;
          } else if (char == '"') {
            inString = false;
          }
          continue;
        }
        if (char == '"') {
          inString = true;
        } else if (char == '{') {
          depth++;
        } else if (char == '}') {
          depth--;
          if (depth == 0) {
            objects.add(body.substring(start, i + 1));
            break;
          }
        }
      }
    }
    return objects;
  }
}
