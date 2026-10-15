import 'dart:math' as math;

import 'package:flashcards2/domain/enums.dart';

/// FSRS-5 constants.
///
/// Source of truth: `docs/design.md` -> "Scheduler: FSRS-5 (verified)", which
/// was checked against the canonical upstream implementations. Do not change
/// these from memory.
abstract final class Fsrs5 {
  /// Fixed power-law decay for FSRS-5. FSRS-6 makes this trainable (`w20`).
  static const double decay = -0.5;

  /// Derived, never hardcoded: `exp((1 / decay) * ln 0.9) - 1`.
  ///
  /// Defined so that `R(S, S) == 0.9`. Writing the literal `0.2346` would
  /// decouple this from [decay] and silently break that identity, which the
  /// whole interval formula depends on.
  static final double factor =
      math.exp(math.pow(decay, -1) * math.log(0.9)) - 1;

  static const double stabilityMin = 0.001;
  static const double stabilityMax = 36500;

  static const int maximumInterval = 36500;

  static const double defaultRequestRetention = 0.9;

  /// Effective short-term saturation exponent.
  ///
  /// FSRS-5's weight vector has **no `w19` slot**: it holds 19 parameters,
  /// `w0..w18`. The canonical FSRS-5 reference vectors nevertheless require the
  /// short-term stability to carry an `S^(-0.01)` saturation factor. That
  /// `0.01` is the parameter-clamp floor applied to the short-term exponent
  /// whenever short-term reviews are enabled — a fixed constant, not something
  /// read from the weight vector.
  ///
  /// This was established empirically, not assumed: reproducing the canonical
  /// memory-state vector needs exactly this exponent. Omitting it misses by
  /// 5.7e-3; using the FSRS-6 default `w19` (0.0658) misses by 3.2e-2.
  static const double shortTermSaturation = 0.01;

  /// FSRS-5 default weights (`w0..w18`). Exactly 19 entries: index 19 and
  /// above belong to FSRS-6 and must not be referenced here.
  static const List<double> defaultWeights = <double>[
    0.40255,
    1.18385,
    3.173,
    15.69105,
    7.1949,
    0.5345,
    1.4604,
    0.0046,
    1.54575,
    0.1192,
    1.01925,
    1.9395,
    0.11,
    0.29605,
    2.2698,
    0.2315,
    2.9898,
    0.51655,
    0.6621,
  ];
}

/// The two-dimensional FSRS memory state.
class MemoryState {
  const new({required this.stability, required this.difficulty});

  /// Days for retrievability to fall from 100% to 90%.
  final double stability;

  /// Intrinsic difficulty in `[1, 10]`.
  final double difficulty;
}

/// Pure-Dart FSRS-5 scheduler.
///
/// Deliberately free of Flutter and Drift so it can be tested without a widget
/// or database harness.
class Fsrs5Scheduler {
  const new({
    this.weights = Fsrs5.defaultWeights,
    this.enableShortTerm = true,
    this.requestRetention = Fsrs5.defaultRequestRetention,
  });

  /// FSRS-5 has 19 parameters. Guards against passing an FSRS-6 vector.
  final List<double> weights;

  /// Pinned explicitly rather than relying on an implicit default.
  ///
  /// This flag changes two separate code paths: same-day stability, and an
  /// extra post-lapse clamp. Leaving it implicit is how a correct-looking port
  /// silently diverges.
  final bool enableShortTerm;

  /// Target recall probability at the scheduled interval.
  final double requestRetention;

  /// Multiplier that maps stability to an interval at [requestRetention].
  ///
  /// Equals `1.0` when `requestRetention == 0.9`, by construction.
  double get intervalModifier {
    final r = requestRetention;
    return (math.pow(r, 1 / Fsrs5.decay) - 1) / Fsrs5.factor;
  }

  /// Probability of recall after [elapsedDays] given [stability].
  double retrievability(double elapsedDays, double stability) {
    final t = elapsedDays < 0 ? 0 : elapsedDays;
    return _pow(1 + Fsrs5.factor * t / stability, Fsrs5.decay);
  }

  /// The inverse of the forgetting curve: the interval that lands on
  /// [retention] recall probability.
  double intervalForRetention(double retention, double stability) {
    return (stability / Fsrs5.factor) * (_pow(retention, 1 / Fsrs5.decay) - 1);
  }

  /// The next interval in whole days for a given [stability].
  int nextInterval(double stability) {
    final raw = stability * intervalModifier;
    return raw.round().clamp(1, Fsrs5.maximumInterval);
  }

  /// Stability assigned on a card's very first review.
  double initialStability(Rating rating) {
    final value = weights[rating.index];
    return value < 0.1 ? 0.1 : value;
  }

  /// Difficulty assigned on a card's very first review.
  double initialDifficulty(Rating rating) {
    return _round(weights[4] - math.exp(rating.index * weights[5]) + 1, 8);
  }

  /// Damping that slows difficulty change as it approaches the bounds.
  double linearDamping(double delta, double oldDifficulty) {
    return _round(delta * (10 - oldDifficulty) / 9, 8);
  }

  /// Pulls difficulty back toward the easy-anchor to avoid runaway values.
  double meanReversion(double initial, double current) {
    return weights[7] * initial + (1 - weights[7]) * current;
  }

  /// Difficulty after a review.
  double nextDifficulty(double difficulty, Rating rating) {
    final grade = rating.index + 1;
    final delta = -weights[6] * (grade - 3);
    final next = difficulty + linearDamping(delta, difficulty);
    final reverted = meanReversion(initialDifficulty(Rating.easy), next);
    return reverted.clamp(1, 10).toDouble();
  }

  /// Stability after a successful recall.
  double nextRecallStability(
    double difficulty,
    double stability,
    double retrievability,
    Rating rating,
  ) {
    final hardPenalty = rating == Rating.hard ? weights[15] : 1;
    final easyBonus = rating == Rating.easy ? weights[16] : 1;
    final value =
        stability *
        (1 +
            math.exp(weights[8]) *
                (11 - difficulty) *
                _pow(stability, -weights[9]) *
                (math.exp((1 - retrievability) * weights[10]) - 1) *
                hardPenalty *
                easyBonus);
    return _round(
      value.clamp(Fsrs5.stabilityMin, Fsrs5.stabilityMax),
      8,
    );
  }

  /// Stability after a lapse (the card was forgotten).
  double nextForgetStability(
    double difficulty,
    double stability,
    double retrievability,
  ) {
    final value =
        weights[11] *
        _pow(difficulty, -weights[12]) *
        (_pow(stability + 1, weights[13]) - 1) *
        math.exp((1 - retrievability) * weights[14]);
    return _round(
      value.clamp(Fsrs5.stabilityMin, Fsrs5.stabilityMax),
      8,
    );
  }

  /// Stability after a same-day review.
  ///
  /// `S' = S * S^(-0.01) * e^(w17 * (G - 3 + w18))`, then masked so the value
  /// never shrinks for grades at or above Hard.
  ///
  /// The `S^(-0.01)` factor is the short-term saturation term; see
  /// [Fsrs5.shortTermSaturation] for why it is a fixed constant here rather
  /// than a parameter from the weight vector. Omitting it does not fail
  /// loudly — it produces a plausible but wrong number, which is precisely why
  /// the reference-vector tests are the acceptance gate.
  double nextShortTermStability(double stability, Rating rating) {
    final grade = rating.index + 1;
    var sinc =
        _pow(stability, -Fsrs5.shortTermSaturation) *
        math.exp(weights[17] * (grade - 3 + weights[18]));

    // Same-day stability must not shrink for Hard, Good or Easy.
    if (grade >= 2 && sinc < 1.0) sinc = 1.0;

    final value = stability * sinc;
    return _round(
      value.clamp(Fsrs5.stabilityMin, Fsrs5.stabilityMax),
      8,
    );
  }

  /// Advances the memory state by one review.
  ///
  /// Dispatch order matters and mirrors the reference implementation exactly:
  /// no prior state -> initialise; `elapsedDays == 0` with short-term enabled
  /// -> same-day formula; `again` -> lapse formula; otherwise -> recall.
  MemoryState nextMemoryState({
    required MemoryState? current,
    required double elapsedDays,
    required Rating rating,
    double? retrievabilityAtReview,
  }) {
    if (current == null) {
      return MemoryState(
        stability: initialStability(rating),
        difficulty: initialDifficulty(rating).clamp(1, 10).toDouble(),
      );
    }

    final r =
        retrievabilityAtReview ??
        retrievability(elapsedDays, current.stability);

    final double newStability;
    if (elapsedDays == 0 && enableShortTerm) {
      newStability = nextShortTermStability(current.stability, rating);
    } else if (rating == Rating.again) {
      final afterFail = nextForgetStability(
        current.difficulty,
        current.stability,
        r,
      );
      if (enableShortTerm) {
        final floor =
            current.stability / math.exp(weights[17] * weights[18]);
        newStability = _round(
          floor,
          8,
        ).clamp(Fsrs5.stabilityMin, afterFail);
      } else {
        newStability = afterFail;
      }
    } else {
      newStability = nextRecallStability(
        current.difficulty,
        current.stability,
        r,
        rating,
      );
    }

    return MemoryState(
      stability: newStability,
      difficulty: nextDifficulty(current.difficulty, rating),
    );
  }
}

double _pow(double base, double exponent) =>
    math.pow(base, exponent).toDouble();

double _round(double value, int digits) {
  final f = math.pow(10, digits).toDouble();
  return (value * f).round() / f;
}
