import 'dart:math' as math;

import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/domain/scheduling/memory_engine.dart';
import 'package:flashcards2/domain/scheduling/memory_state.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

/// Anti-corruption layer between the domain scheduler and `package:fsrs`
/// (FSRS-6, 21 parameters).
///
/// Third-party types never cross this boundary: callers see only
/// [MemoryState] and [Rating]. What crosses into the package is a
/// fabricated [fsrs.Card] per call; what comes back is the two memory
/// variables. The package's own [fsrs.State] machine, step lists, and
/// computed `due` are extracted-or-discarded here, never propagated.
///
/// Granularity recipe (validated by the Phase 1 spike,
/// docs/fsrs6_migration_plan.md):
///
/// - The driver is the package's `reviewCard`, whose `reviewDateTime` is
///   caller-supplied, so the adapter injects explicit `elapsedDays` by
///   fabricating UTC timestamps (the package requires UTC and would throw
///   `ArgumentError` on local times).
/// - The wrapped scheduler is built with **empty** learning/relearning step
///   lists, so every review lands on the package's day-scale `_nextInterval`
///   path. The domain owns all step arithmetic itself (`Scheduler` in
///   `scheduler.dart`); the package's step machine stays inert by
///   construction. This also makes interval extraction exact:
///   `nextInterval(s)` for the memory state just produced equals
///   `due - reviewDateTime` of the same `reviewCard` call, which is the
///   ONLY public path to the package's interval (its `_nextInterval` is
///   private).
///
/// Decisions pinned by the migration plan (Phase 2):
///
/// - **Option A (same-day governance):** during learning/relearning the
///   domain assigns intervals from its own step lists; this adapter only
///   advances (S, D), using the package's same-day `w19` formula.
/// - **Package behavior accepted as-is** for same-day `hard`: it may
///   *decrease* stability (the package clamps the same-day increase to
///   `>= 1` for `good`/`easy` only), deviating from py-fsrs/fsrs-rs. Do not
///   "fix" that here; compensation, if ever wanted, comes in behind this
///   boundary with its own tests.
/// - **Fuzz policy:** ON in production (constructor default), OFF in every
///   test harness via `enableFuzzing: false`.
class Fsrs6SchedulerAdapter implements MemoryEngine {
  /// Creates the adapter around a default-parameter FSRS-6 scheduler.
  ///
  /// [enableFuzzing] defaults to `true` — the Anki-compatible production
  /// behavior. Test harnesses MUST pass `false`: interval extraction
  /// through fabricated `due` values is only deterministic without fuzz.
  new({
    this.enableFuzzing = true,
    List<double> parameters = fsrs.defaultParameters,
    this.desiredRetention = 0.9,
    this.maximumInterval = 36500,
  }) : parameters = List<double>.unmodifiable(parameters) {
    _scheduler = fsrs.Scheduler(
      parameters: this.parameters,
      desiredRetention: desiredRetention,
      learningSteps: const [],
      relearningSteps: const [],
      maximumInterval: maximumInterval,
      enableFuzzing: enableFuzzing,
    );
  }

  /// Whether the wrapped scheduler applies Anki-style interval fuzzing.
  ///
  /// Defaults to `true` for production; every test harness passes `false`.
  final bool enableFuzzing;

  /// The 21-parameter FSRS-6 weight vector ([fsrs.defaultParameters]).
  final List<double> parameters;

  /// Target recall probability at the scheduled interval.
  final double desiredRetention;

  /// Upper bound for a scheduled interval, in days.
  final int maximumInterval;

  late final fsrs.Scheduler _scheduler;

  // Pairing cache: `nextInterval` is always invoked with the stability
  // just produced by `nextMemoryState` (see Scheduler._graduate). When the
  // queried stability is exactly the produced one, the interval extracted
  // from that same reviewCard call is the package's own value — fuzz
  // included in production. Any other query falls back to the closed-form
  // interval computed from the scheduler's public parameters.
  double? _lastProducedStability;
  int? _lastProducedIntervalDays;

  /// Fixed fabricated clock origin. Absolute dates are irrelevant — only
  /// the day deltas between fabrication and review matter.
  static final DateTime _t0 = DateTime.utc(2020);

  /// Advances the memory state by one review.
  ///
  /// [elapsedDays] is the domain's cutoff-aware whole-day count (the same
  /// day-index value the domain `Scheduler` computes); it is injected into
  /// the package through fabricated timestamps. A `null` [current] is the
  /// card's first review and initializes (S, D) from the rating.
  @override
  MemoryState nextMemoryState({
    required Rating rating,
    MemoryState? current,
    double elapsedDays = 0,
  }) {
    final packageRating = fsrs.Rating.fromValue(rating.index + 1);
    final elapsed = elapsedDays < 0 ? 0 : elapsedDays.round();

    // The memory update math inside reviewCard is state-independent given
    // (S, D, elapsedDays): every state branches into the same
    // short-term/recall/lapse formulas. The card's fsrs.State only steers
    // the step/interval machinery, which the empty-step configuration has
    // already neutralized — except the initial state, which must be
    // `learning` with null S/D to take the initialization branch.
    final card = current == null
        ? fsrs.Card(cardId: 0)
        : fsrs.Card(
            cardId: 0,
            state: fsrs.State.review,
            stability: current.stability,
            difficulty: current.difficulty,
            lastReview: _t0.subtract(Duration(days: elapsed)),
          );

    final reviewed = _scheduler
        .reviewCard(card, packageRating, reviewDateTime: _t0)
        .card;

    // With fuzz enabled the extracted interval is fuzzy by design; the
    // pairing cache then carries exactly the interval the package chose.
    _lastProducedStability = reviewed.stability;
    _lastProducedIntervalDays =
        reviewed.due.difference(_t0).inDays.clamp(1, maximumInterval);

    return MemoryState(
      stability: reviewed.stability!,
      difficulty: reviewed.difficulty!,
    );
  }

  /// The next interval in whole days for [stability].
  ///
  /// Uses the interval extracted from the preceding [nextMemoryState] call
  /// when [stability] is the state that call produced; otherwise computes
  /// the closed-form FSRS interval from the scheduler's public parameters —
  /// the same formula as the package's private `_nextInterval`, derived
  /// live so a future optimized weight vector stays consistent.
  @override
  int nextInterval(double stability) {
    if (stability == _lastProducedStability &&
        _lastProducedIntervalDays != null) {
      return _lastProducedIntervalDays!;
    }

    final decay = -parameters[20];
    final factor = math.pow(0.9, 1 / decay) - 1;
    final raw =
        (stability / factor) * (math.pow(desiredRetention, 1 / decay) - 1);
    return raw.round().clamp(1, maximumInterval);
  }
}
