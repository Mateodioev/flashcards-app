/// A calibration trial: predict a score, then actually score it.
class CalibrationTrial {
  const new({required this.predicted, required this.actual});

  /// What the learner expected to score, in `[0, 1]`.
  final double predicted;

  /// What they actually scored, in `[0, 1]`.
  final double actual;

  /// Positive means overconfident: predicted higher than achieved.
  double get bias => predicted - actual;
}

/// How well the learner's self-assessment tracks reality.
enum CalibrationVerdict {
  /// Predictions run reliably above results.
  overconfident,

  /// Predictions track results closely.
  calibrated,

  /// Predictions run reliably below results.
  underconfident,

  /// Too few trials to conclude anything.
  insufficient,
}

/// The onboarding decision this probe produces.
class CalibrationResult {
  const new({
    required this.verdict,
    required this.meanBias,
    required this.sampleSize,
    required this.forcedGenerationBarrierDefault,
  });

  final CalibrationVerdict verdict;

  /// Mean `predicted - actual` across trials. Positive is overconfidence.
  final double meanBias;

  final int sampleSize;

  /// Whether the Forced Generation Barrier should default to on.
  ///
  /// On when the learner is overconfident: the fluency illusion is the specific
  /// failure this barrier exists to defeat, so it is enabled precisely for the
  /// learner most susceptible to it.
  final bool forcedGenerationBarrierDefault;
}

/// Measures the gap between predicted and actual performance.
///
/// This targets the **fluency heuristic** — the well-evidenced tendency for
/// self-assessment to run ahead of real retrieval. It is *not* a learning-style
/// inventory: the source material demolishes the VAK neuromyth, and nothing
/// here asks how the learner prefers to be taught. It asks only how well their
/// judgement of their own recall matches their recall.
class CalibrationProbe {
  const new({
    this.overconfidentAt = 0.15,
    this.underconfidentAt = -0.15,
    this.minimumSample = 3,
    this.trials = const <CalibrationTrial>[],
  });

  /// Mean bias at or above this counts as overconfident.
  final double overconfidentAt;

  /// Mean bias at or below this counts as underconfident.
  final double underconfidentAt;

  final int minimumSample;
  final List<CalibrationTrial> trials;

  CalibrationProbe withTrial(CalibrationTrial trial) {
    return CalibrationProbe(
      overconfidentAt: overconfidentAt,
      underconfidentAt: underconfidentAt,
      minimumSample: minimumSample,
      trials: <CalibrationTrial>[...trials, trial],
    );
  }

  CalibrationResult get result {
    if (trials.length < minimumSample) {
      return CalibrationResult(
        verdict: CalibrationVerdict.insufficient,
        meanBias: 0,
        sampleSize: trials.length,
        forcedGenerationBarrierDefault: false,
      );
    }

    final total = trials.fold<double>(0, (sum, t) => sum + t.bias);
    final meanBias = total / trials.length;

    if (meanBias >= overconfidentAt) {
      return CalibrationResult(
        verdict: CalibrationVerdict.overconfident,
        meanBias: meanBias,
        sampleSize: trials.length,
        forcedGenerationBarrierDefault: true,
      );
    }
    if (meanBias <= underconfidentAt) {
      return CalibrationResult(
        verdict: CalibrationVerdict.underconfident,
        meanBias: meanBias,
        sampleSize: trials.length,
        forcedGenerationBarrierDefault: false,
      );
    }
    return CalibrationResult(
      verdict: CalibrationVerdict.calibrated,
      meanBias: meanBias,
      sampleSize: trials.length,
      forcedGenerationBarrierDefault: false,
    );
  }
}
