import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/domain/scheduling/memory_state.dart';

/// The memory-math engine the domain `Scheduler` delegates to.
///
/// The domain owns the step state machine, due arithmetic, and the
/// day-cutoff calendar; the engine only advances the continuous memory
/// variables (stability, difficulty) and maps a stability to a whole-day
/// interval. `Fsrs5Scheduler` (legacy, kept frozen as the rollback path per
/// docs/fsrs6_migration_plan.md Phase 6) and `Fsrs6SchedulerAdapter` (the
/// anti-corruption layer over `package:fsrs`) both implement this contract,
/// which is what makes the FSRS-6 migration — and any rollback — a config
/// swap rather than a rewrite of `scheduler.dart`.
abstract interface class MemoryEngine {
  /// Advances the memory state by one review.
  ///
  /// A `null` [current] is the card's first review and initializes the
  /// state from the rating. [elapsedDays] is the domain's cutoff-aware
  /// whole-day count.
  MemoryState nextMemoryState({
    required MemoryState? current,
    required Rating rating,
    required double elapsedDays,
  });

  /// The next interval in whole days for [stability].
  int nextInterval(double stability);
}
