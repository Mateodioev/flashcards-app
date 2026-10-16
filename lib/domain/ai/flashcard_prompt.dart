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

  /// Repairs LaTeX backslashes that JSON decoding would mangle or reject.
  ///
  /// JSON accepts these after a backslash inside a string:
  ///
  ///  * `"` `\` `/` — complete escapes.
  ///  * `b` `f` `n` `r` `t` — single-character control escapes.
  ///  * `u` plus four hex digits — a unicode escape.
  ///
  /// Anything else (`\i`, `\s`, `\a`, `\,`, `\{`) is INVALID JSON and makes the
  /// whole document unparseable. The unparseable cases are unambiguous, so only
  /// the valid-but-suspicious ones need judgement:
  ///
  ///  * `\b` and `\f` are **always** repaired. A backspace or form feed is never
  ///    wanted in card text, while `\beta`, `\bmod`, `\frac` and `\forall` are
  ///    ordinary. Repairing costs nothing and rescues real content.
  ///  * `\n`, `\r` and `\t` are genuinely ambiguous, and are decided by
  ///    **math-span context**: a newline, tab or carriage return is what a
  ///    model means in prose, and `\nu`, `\nabla`, `\rho`, `\to`, `\tan` and
  ///    `\times` are only ever written inside `$...$`. This uses the same
  ///    boundary the span parser uses rather than inventing a second one.
  ///
  /// Two earlier versions failed, and both were caught by probing rather
  /// than by reading:
  ///
  ///  1. A hand-written list of ~70 command names. That is a blocklist, and
  ///     `\int` and `\sqrt` — routine in real notes — were not on it, so a
  ///     model emitting them unescaped lost the ENTIRE batch to a JSON error,
  ///     while `\bar` slipped through as a silent backspace.
  ///  2. A rule treating "a letter run of two or more" as proof of LaTeX. That
  ///     mangled `"line1\nline2"` — the run is `nline`, which is not a command
  ///     at all — turning a real newline into literal text. Run length simply
  ///     does not carry that information.
  static String _repairLatexEscapes(String source) {
    final buffer = StringBuffer();
    var i = 0;
    var inMath = false;

    while (i < source.length) {
      final char = source[i];

      // Track dollar delimiters so the ambiguous `\n`-family case has context.
      // An escaped `\$` must NOT toggle this, which is why every backslash
      // branch below advances past both characters.
      if (char == r'$') {
        inMath = !inMath;
        buffer.write(char);
        i++;
        continue;
      }

      if (char != r'\' || i + 1 >= source.length) {
        buffer.write(char);
        i++;
        continue;
      }

      final next = source[i + 1];

      // JSON's own complete escapes. Rewriting any of these breaks the document
      // — doubling `\"` terminates the string early. Never LaTeX.
      if (next == '"' || next == '/' || next == r'\') {
        buffer.write(source.substring(i, i + 2));
        i += 2;
        continue;
      }

      // `\uXXXX` is a legal unicode escape; leave it exactly as written.
      if (next == 'u' && _hasFourHexDigits(source, i + 2)) {
        buffer.write(source.substring(i, i + 6));
        i += 6;
        continue;
      }

      // Always LaTeX: a backspace or form feed is never wanted in a card, and
      // `\beta`, `\bmod`, `\frac`, `\forall` are common.
      if (next == 'b' || next == 'f') {
        buffer.write('\\\\$next');
        i += 2;
        continue;
      }

      // Ambiguous control escapes: a real newline/tab/carriage return in prose,
      // or a command like `\nu` inside maths.
      if (next == 'n' || next == 'r' || next == 't') {
        if (inMath) {
          buffer.write('\\\\$next');
        } else {
          buffer.write(source.substring(i, i + 2));
        }
        i += 2;
        continue;
      }

      // Everything else is LaTeX. Letters (`\int`, `\sqrt`, `\alpha`) make the
      // document invalid; punctuation (`\,`, `\{`, `\%`, `\&`) does too.
      //
      // This is NOT a raw string: the interpolation of `$next` is the point. In
      // a raw string it would emit the literal characters.
      buffer.write('\\\\$next');
      i += 2;
    }

    return buffer.toString();
  }

  static bool _hasFourHexDigits(String source, int start) {
    if (start + 4 > source.length) return false;
    for (var i = start; i < start + 4; i++) {
      final code = source.codeUnitAt(i);
      final isDigit = code >= 0x30 && code <= 0x39;
      final isLower = code >= 0x61 && code <= 0x66;
      final isUpper = code >= 0x41 && code <= 0x46;
      if (!isDigit && !isLower && !isUpper) return false;
    }
    return true;
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
