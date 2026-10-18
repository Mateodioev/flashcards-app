/// The two-dimensional FSRS memory state.
///
/// Engine-neutral: both `Fsrs5Scheduler` and `Fsrs6SchedulerAdapter`
/// produce and consume this type. It lives in its own module so the
/// `MemoryEngine` contract does not depend on either engine's file.
class MemoryState {
  const new({required this.stability, required this.difficulty});

  /// Days for retrievability to fall from 100% to 90%.
  final double stability;

  /// Intrinsic difficulty in `[1, 10]`.
  final double difficulty;
}
