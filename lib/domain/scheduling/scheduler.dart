import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/domain/scheduling/fsrs5.dart';

/// A card's full scheduling position.
///
/// [step] is the index into the active step list for [state] — the learning
/// steps while `learning`, the relearning steps while `relearning`. It is
/// meaningless in `new_` and `review` and is persisted anyway so a card can
/// re-enter learning without losing its place.
class CardSchedule {
  const new({
    required this.state,
    this.step = 0,
    this.reps = 0,
    this.lapses = 0,
    this.memory,
    this.due,
    this.lastReview,
  });

  /// A card that has never been reviewed.
  const new newCard()
    : state = ReviewState.new_,
      step = 0,
      reps = 0,
      lapses = 0,
      memory = null,
      due = null,
      lastReview = null;

  final ReviewState state;
  final int step;
  final int reps;
  final int lapses;

  /// Null until the first review.
  final MemoryState? memory;

  final DateTime? due;
  final DateTime? lastReview;
}

/// Sub-day step configuration.
///
/// The canonical FSRS reference vectors were produced by the raw algorithm,
/// which graduates a card on the first successful learning review — that is
/// [singleStep]. Anki-style scheduling uses [ankiDefault].
class SchedulerConfig {
  const new({
    this.learningSteps = singleStep,
    this.relearningSteps = singleStep,
    this.fsrs = const Fsrs5Scheduler(),
    this.dayCutoffHour = defaultDayCutoffHour,
  });

  /// Hour (0-23) at which a new scheduling day begins, in local time.
  ///
  /// 4am by default: a review made at 2am still belongs to the previous day.
  static const int defaultDayCutoffHour = 4;

  /// One sub-day step: a new card gets one same-day review, then graduates.
  static const List<Duration> singleStep = <Duration>[Duration(minutes: 1)];

  /// Anki's default *learning* steps: `1m`, then `10m`.
  static const List<Duration> ankiLearning = <Duration>[
    Duration(minutes: 1),
    Duration(minutes: 10),
  ];

  /// Anki's default *relearning* steps: a single `10m`.
  ///
  /// Deliberately not the same list as [ankiLearning]. Lapses re-enter a single
  /// short step, not the whole learning ladder, so a recovered card returns to
  /// the review queue after one successful recall.
  static const List<Duration> ankiRelearning = <Duration>[
    Duration(minutes: 10),
  ];

  /// Anki's defaults for both step lists.
  static const List<Duration> ankiDefault = ankiLearning;

  final List<Duration> learningSteps;
  final List<Duration> relearningSteps;
  final Fsrs5Scheduler fsrs;
  final int dayCutoffHour;
}

/// The result of applying one rating.
class ReviewOutcome {
  const new({
    required this.schedule,
    required this.scheduledDays,
    required this.elapsedDays,
  });

  final CardSchedule schedule;

  /// The interval the card was scheduled for, in **whole days**.
  ///
  /// Sub-day learning steps floor to `0`, matching the reference semantics
  /// where `scheduled_days` is an integer day count. The precise instant is on
  /// the schedule's `due`.
  final int scheduledDays;

  /// Whole days since the previous review, floored — this is what the FSRS
  /// memory math sees, so a same-day review reads as `t == 0`.
  final int elapsedDays;
}

/// Drives [Fsrs5Scheduler] with learning steps and card states.
///
/// Pure Dart: no Flutter, no Drift, no clock. Every method takes `now`.
class Scheduler {
  const new([this.config = const SchedulerConfig()]);

  final SchedulerConfig config;

  Fsrs5Scheduler get _fsrs => config.fsrs;

  /// Whole days between [from] and [to], honouring the [cutoffHour].
  ///
  /// "Days" are calendar days shifted by the cutoff, not 24-hour blocks: with a
  /// 4am cutoff, a review at 2am belongs to the previous day. This matches how
  /// a learner experiences a day, and it is why a plain
  /// `difference.inDays` is wrong here.
  ///
  /// The canonical reference vectors are unaffected by the cutoff, because
  /// every interval they schedule lands on an exact multiple of a day.
  static int elapsedDays(
    DateTime from,
    DateTime to, {
    int cutoffHour = SchedulerConfig.defaultDayCutoffHour,
  }) {
    final delta = dayIndex(to, cutoffHour) - dayIndex(from, cutoffHour);
    return delta < 0 ? 0 : delta;
  }

  /// The shifted calendar-day number [instant] falls in.
  ///
  /// Converted to local time first, so the cutoff means "4am where the learner
  /// is". The epoch arithmetic is done in UTC purely to avoid DST skew in the
  /// day *count*; the calendar date itself comes from the shifted local value.
  static int dayIndex(
    DateTime instant, [
    int cutoffHour = SchedulerConfig.defaultDayCutoffHour,
  ]) {
    final shifted = instant.toLocal().subtract(Duration(hours: cutoffHour));
    return DateTime.utc(
      shifted.year,
      shifted.month,
      shifted.day,
    ).difference(DateTime.utc(1970)).inDays;
  }

  /// Applies one rating and returns the card's new position.
  ReviewOutcome review({
    required CardSchedule card,
    required Rating rating,
    required DateTime now,
  }) {
    final elapsed = card.lastReview == null
        ? 0
        : elapsedDays(card.lastReview!, now, cutoffHour: config.dayCutoffHour);

    final memory = _fsrs.nextMemoryState(
      current: card.memory,
      elapsedDays: elapsed.toDouble(),
      rating: rating,
    );

    final next = switch (card.state) {
      ReviewState.new_ => _fromNew(card, rating, memory, now),
      ReviewState.learning => _fromLearning(card, rating, memory, now),
      ReviewState.review => _fromReview(card, rating, memory, now),
      ReviewState.relearning => _fromRelearning(card, rating, memory, now),
    };

    return ReviewOutcome(
      schedule: next,
      scheduledDays: next.due == null
          ? 0
          : next.due!.difference(now).inMinutes ~/ Duration.minutesPerDay,
      elapsedDays: elapsed,
    );
  }

  CardSchedule _fromNew(
    CardSchedule card,
    Rating rating,
    MemoryState memory,
    DateTime now,
  ) {
    // Easy graduates immediately; everything else enters the learning steps.
    if (rating == Rating.easy || config.learningSteps.isEmpty) {
      return _graduate(card, memory, now, lapse: false);
    }
    return _enterSteps(
      card,
      memory,
      now,
      steps: config.learningSteps,
      step: 0,
      state: ReviewState.learning,
    );
  }

  CardSchedule _fromLearning(
    CardSchedule card,
    Rating rating,
    MemoryState memory,
    DateTime now,
  ) {
    final steps = config.learningSteps;
    switch (rating) {
      case Rating.again:
        return _enterSteps(
          card,
          memory,
          now,
          steps: steps,
          step: 0,
          state: ReviewState.learning,
        );
      case Rating.hard:
        // Repeat the current step without advancing.
        return _enterSteps(
          card,
          memory,
          now,
          steps: steps,
          step: card.step.clamp(0, steps.length - 1),
          state: ReviewState.learning,
        );
      case Rating.good:
      case Rating.easy:
        final advanced = card.step + 1;
        if (rating == Rating.easy || advanced >= steps.length) {
          return _graduate(card, memory, now, lapse: false);
        }
        return _enterSteps(
          card,
          memory,
          now,
          steps: steps,
          step: advanced,
          state: ReviewState.learning,
        );
    }
  }

  CardSchedule _fromReview(
    CardSchedule card,
    Rating rating,
    MemoryState memory,
    DateTime now,
  ) {
    if (rating == Rating.again) {
      if (config.relearningSteps.isEmpty) {
        return _graduate(card, memory, now, lapse: true);
      }
      return _enterSteps(
        card,
        memory,
        now,
        steps: config.relearningSteps,
        step: 0,
        state: ReviewState.relearning,
        lapse: true,
      );
    }
    return _graduate(card, memory, now, lapse: false);
  }

  CardSchedule _fromRelearning(
    CardSchedule card,
    Rating rating,
    MemoryState memory,
    DateTime now,
  ) {
    final steps = config.relearningSteps;
    switch (rating) {
      case Rating.again:
        return _enterSteps(
          card,
          memory,
          now,
          steps: steps,
          step: 0,
          state: ReviewState.relearning,
        );
      case Rating.hard:
        return _enterSteps(
          card,
          memory,
          now,
          steps: steps,
          step: card.step.clamp(0, steps.length - 1),
          state: ReviewState.relearning,
        );
      case Rating.good:
      case Rating.easy:
        final advanced = card.step + 1;
        if (rating == Rating.easy || advanced >= steps.length) {
          return _graduate(card, memory, now, lapse: false);
        }
        return _enterSteps(
          card,
          memory,
          now,
          steps: steps,
          step: advanced,
          state: ReviewState.relearning,
        );
    }
  }

  /// Schedules the next sub-day step.
  CardSchedule _enterSteps(
    CardSchedule card,
    MemoryState memory,
    DateTime now, {
    required List<Duration> steps,
    required int step,
    required ReviewState state,
    bool lapse = false,
  }) {
    final offset = steps.isEmpty ? Duration.zero : steps[step];
    return CardSchedule(
      state: state,
      step: step,
      reps: card.reps + 1,
      lapses: lapse ? card.lapses + 1 : card.lapses,
      memory: memory,
      due: now.add(offset),
      lastReview: now,
    );
  }

  /// Moves the card to the review state with a day-scale interval.
  CardSchedule _graduate(
    CardSchedule card,
    MemoryState memory,
    DateTime now, {
    required bool lapse,
  }) {
    final interval = _fsrs.nextInterval(memory.stability);
    return CardSchedule(
      state: ReviewState.review,
      reps: card.reps + 1,
      lapses: lapse ? card.lapses + 1 : card.lapses,
      memory: memory,
      due: now.add(Duration(days: interval)),
      lastReview: now,
    );
  }
}
