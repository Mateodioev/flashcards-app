import 'dart:math';

/// One recall trial: reproduce the digit sequence, in order.
class MemorySpanTrial {
  const new({required this.digits});

  final List<int> digits;

  int get length => digits.length;

  /// Order matters. A correct set in the wrong order is still a failure.
  bool isCorrect(List<int> response) {
    if (response.length != digits.length) return false;
    for (var i = 0; i < digits.length; i++) {
      if (response[i] != digits[i]) return false;
    }
    return true;
  }
}

/// Outcome of a span session.
class MemorySpanOutcome {
  const new({required this.span, required this.trialsTaken});

  /// Longest sequence recalled correctly. `0` means none were.
  final int span;

  final int trialsTaken;
}

/// Adaptive working-memory span session.
///
/// Climb on success, retry once at the same length on failure, and stop after
/// the retries at one length are exhausted. The span is the longest length
/// passed.
///
/// A seeded generator makes every session reproducible in tests.
class MemorySpanSession {
  new({
    required int seed,
    this.startLength = 3,
    this.maxLength = 9,
    this.retriesPerLength = 1,
  }) : _random = Random(seed) {
    _current = MemorySpanTrial(digits: _generate(startLength));
  }

  final int startLength;
  final int maxLength;
  final int retriesPerLength;
  final Random _random;

  late MemorySpanTrial _current;
  int _failuresHere = 0;
  int _trials = 0;
  int _best = 0;
  bool _complete = false;

  MemorySpanTrial get current => _current;

  bool get isComplete => _complete;

  int get trialsTaken => _trials;

  /// The longest length recalled correctly. Only meaningful once complete.
  int get best => _best;

  MemorySpanOutcome get outcome =>
      MemorySpanOutcome(span: _best, trialsTaken: _trials);

  List<int> _generate(int length) {
    return <int>[for (var i = 0; i < length; i++) _random.nextInt(9) + 1];
  }

  /// Records an attempt and advances the session.
  void submit(List<int> response) {
    if (_complete) {
      throw StateError('session already complete');
    }
    _trials++;

    final attempted = _current.length;
    final passed = _current.isCorrect(response);

    if (passed) {
      if (attempted > _best) _best = attempted;
      _failuresHere = 0;
      if (attempted >= maxLength) {
        _complete = true;
        return;
      }
      _current = MemorySpanTrial(digits: _generate(attempted + 1));
      return;
    }

    _failuresHere++;
    if (_failuresHere > retriesPerLength) {
      _complete = true;
      return;
    }
    // Same length again, but a fresh sequence, so the length is what is tested.
    _current = MemorySpanTrial(digits: _generate(attempted));
  }
}

/// Defaults derived from a span session.
///
/// **These are engineering choices, not validated laws.** No published formula
/// maps a working-memory span onto an optimal number of new cards per day. What
/// *is* grounded is the chunk ceiling: Cowan's 4±1 bound means a card must not
/// ask the learner to hold more than a handful of items at once.
abstract final class MemorySpanDefaults {
  /// Cowan's `4 ± 1` window, clamped to a usable range.
  static int contentChunkLimit(int span) {
    if (span <= 3) return 3;
    if (span >= 5) return 5;
    return 4;
  }

  /// A deliberately conservative ramp.
  ///
  /// A heuristic, and labelled as one wherever it is shown. Erring low is the
  /// safe direction: too many new cards produces a review backlog the learner
  /// cannot clear, which is how spaced-repetition apps get abandoned.
  static int newCardsPerDay(int span) {
    if (span <= 2) return 3;
    if (span == 3) return 5;
    if (span == 4) return 8;
    if (span == 5) return 12;
    return 15;
  }

  /// Used when onboarding is skipped or a session never completes.
  static const int fallbackSpan = 4;
}
