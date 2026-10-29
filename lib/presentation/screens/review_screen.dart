import 'package:flashcards2/domain/entities/scheduling.dart' as domain;
import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/domain/scheduling/fsrs5.dart';
import 'package:flashcards2/domain/scheduling/scheduler.dart';
import 'package:flashcards2/domain/scheduling/session.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flashcards2/presentation/widgets/card_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runs one review session, then shows an honest summary.
///
/// One card at a time, single focus. The rating controls stay hidden until the
/// answer is revealed, so a rating cannot be given before the learner has
/// actually seen whether they were right.
class ReviewScreen extends ConsumerStatefulWidget {
  const new({
    required this.items,
    required this.scheduler,
    required this.barrierEnabled,
    super.key,
  });

  final List<SessionItem> items;

  /// Injected so a session can be driven with a fixed clock in tests.
  final Scheduler scheduler;

  /// When true, the answer stays hidden until the learner attempts recall.
  final bool barrierEnabled;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final _recall = TextEditingController();

  int _index = 0;
  bool _revealed = false;
  bool _attempted = false;

  /// Set when the learner says they answered aloud rather than typing.
  bool _attemptedAloud = false;

  DateTime? _shownAt;
  final _ratings = <Rating>[];

  /// The next interval each rating would produce for the current card, shown
  /// under the buttons after reveal so the learner chooses with the
  /// consequence in view.
  Map<Rating, String>? _previews;

  SessionItem get _current => widget.items[_index];

  bool get _isLast => _index == widget.items.length - 1;

  /// The barrier blocks the reveal until the learner has produced something.
  ///
  /// Typing counts, and so does explicitly acknowledging an answer given aloud
  /// — otherwise a learner who prefers to answer verbally would be stuck behind
  /// a keyboard they do not need.
  bool get _canReveal =>
      !widget.barrierEnabled ||
      _recall.text.trim().isNotEmpty ||
      _attemptedAloud;

  @override
  void initState() {
    super.initState();
    _shownAt = DateTime.now();
  }

  @override
  void dispose() {
    _recall.dispose();
    super.dispose();
  }

  Future<void> _rate(Rating rating) async {
    final now = DateTime.now();
    final durationMs = _shownAt == null
        ? 0
        : now.difference(_shownAt!).inMilliseconds;

    final repository = ref.read(cardRepositoryProvider);

    // Load the card's current schedule, or start one from scratch.
    final existing = await repository.findScheduleState(_current.cardId);
    final card = _scheduleFromState(existing);

    final outcome = widget.scheduler.review(
      card: card,
      rating: rating,
      now: now,
    );
    final schedule = outcome.schedule;

    await repository.upsertScheduleState(_toState(_current.cardId, schedule));
    await ref
        .read(reviewLogRepositoryProvider)
        .append(
          domain.ReviewLog(
            id: 0,
            cardId: _current.cardId,
            rating: rating,
            reviewedAt: now,
            elapsedDays: outcome.elapsedDays.toDouble(),
            scheduledDays: outcome.scheduledDays.toDouble(),
            state: schedule.state,
            durationMs: durationMs,
            hintUsed: false,
            barrierCompleted: _attempted,
          ),
        );

    if (!mounted) return;
    setState(() {
      _ratings.add(rating);
      if (_isLast) {
        _index = widget.items.length;
      } else {
        _index++;
        _revealed = false;
        _attempted = false;
        _previews = null;
        _recall.clear();
        _shownAt = DateTime.now();
      }
    });
  }

  /// Sub-day steps read as minutes/hours, graduated cards as days; the exact
  /// FSRS instant stays on the schedule, only the display is coarse.
  String _formatInterval(Duration delta) {
    if (delta.inMinutes < 60) return '${delta.inMinutes}m';
    if (delta.inHours < 24) return '${delta.inHours}h';
    return '${delta.inDays}d';
  }

  domain.ScheduleState _toState(int cardId, CardSchedule schedule) {
    final memory = schedule.memory;
    return domain.ScheduleState(
      cardId: cardId,
      stability: memory?.stability ?? 0,
      difficulty: memory?.difficulty ?? 0,
      due: schedule.due ?? DateTime.now(),
      reps: schedule.reps,
      lapses: schedule.lapses,
      state: schedule.state,
      step: schedule.step,
      lastReview: schedule.lastReview,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_index >= widget.items.length) {
      return _SessionSummary(ratings: _ratings);
    }
    return _buildCard(context);
  }

  Widget _buildCard(BuildContext context) {
    final cardAsync = ref.watch(cardByIdProvider(_current.cardId));

    return Scaffold(
      appBar: AppBar(
        title: Text('${_index + 1} of ${widget.items.length}'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _confirmEndSession(context),
          tooltip: 'End session',
        ),
      ),
      body: cardAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            const Center(child: Text('Could not load this card.')),
        data: (card) {
          if (card == null) {
            return const Center(child: Text('Card no longer exists.'));
          }
          return Column(
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (_current.isNew) const _NewBadge(),
                      CardContent(
                        card.front,
                        textStyle: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (widget.barrierEnabled && !_revealed) ...<Widget>[
                        const SizedBox(height: 24),
                        _RecallField(
                          controller: _recall,
                          attemptedAloud: _attemptedAloud,
                          onChanged: () => setState(() {}),
                          onAnsweredAloud: () => setState(
                            () => _attemptedAloud = !_attemptedAloud,
                          ),
                        ),
                      ],
                      if (_revealed) ...<Widget>[
                        const Divider(height: 48),
                        CardContent(card.back),
                        const SizedBox(height: 16),
                        _SelfCheckHint(
                          attempted: _attempted,
                          recall: _recall.text,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              _BottomBar(
                revealed: _revealed,
                canReveal: _canReveal,
                previews: _previews,
                onReveal: _reveal,
                onRate: _rate,
              ),
            ],
          );
        },
      ),
    );
  }

  /// The single place a persisted schedule row becomes a [CardSchedule].
  CardSchedule _scheduleFromState(domain.ScheduleState? existing) {
    if (existing == null) return const CardSchedule.newCard();
    return CardSchedule(
      state: existing.state,
      step: existing.step,
      reps: existing.reps,
      lapses: existing.lapses,
      memory: existing.stability == 0 && existing.difficulty == 0
          ? null
          : MemoryState(
              stability: existing.stability,
              difficulty: existing.difficulty,
            ),
      due: existing.due,
      lastReview: existing.lastReview,
    );
  }

  /// Anki teaches calibration by showing what each grade buys; the same
  /// honesty this app asks for in grading deserves to be visible in the
  /// buttons. Previews are advisory: a load or compute failure drops them
  /// silently and grading still works.
  Future<Map<Rating, String>?> _computePreviews() async {
    final existing = await ref
        .read(cardRepositoryProvider)
        .findScheduleState(_current.cardId);
    final card = _scheduleFromState(existing);
    final now = DateTime.now();
    return <Rating, String>{
      for (final rating in Rating.values)
        rating: _formatInterval(
          widget.scheduler
              .review(card: card, rating: rating, now: now)
              .schedule
              .due!
              .difference(now),
        ),
    };
  }

  Future<void> _reveal() async {
    Map<Rating, String>? previews;
    try {
      previews = await _computePreviews();
    } on Object {
      previews = null;
    }
    if (!mounted) return;
    setState(() {
      _revealed = true;
      _attempted = _recall.text.trim().isNotEmpty || _attemptedAloud;
      _previews = previews;
    });
  }

  /// A stray tap used to kill the session — and with it the summary the
  /// learner never got to see. Ratings are already persisted per card, so the
  /// dialog can honestly promise nothing is lost, but leaving is still a
  /// deliberate act.
  Future<void> _confirmEndSession(BuildContext context) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('End session?'),
        content: const Text('Your ratings so far are saved.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep studying'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('End session'),
          ),
        ],
      ),
    );
    if ((leave ?? false) && context.mounted) {
      Navigator.of(context).pop();
    }
  }
}

/// Marks a first-time card so the learner knows why it feels unfamiliar.
class _NewBadge extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'New',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: scheme.onSecondaryContainer),
          ),
        ),
      ),
    );
  }
}

class _RecallField extends StatelessWidget {
  const new({
    required this.controller,
    required this.attemptedAloud,
    required this.onChanged,
    required this.onAnsweredAloud,
  });

  final TextEditingController controller;
  final bool attemptedAloud;
  final VoidCallback onChanged;
  final VoidCallback onAnsweredAloud;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Answer from memory before revealing.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          onChanged: (_) => onChanged(),
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Type what you remember',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        // Some recall is spoken, not typed. Without this the barrier would
        // demand a keyboard and would be unsatisfiable for anyone who does not
        // want one.
        CheckboxListTile(
          value: attemptedAloud,
          onChanged: (_) => onAnsweredAloud(),
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('I answered aloud'),
        ),
      ],
    );
  }
}

/// Points at the gap between what was recalled and what the card says.
///
/// This is the anti-fluency check: seeing your own answer beside the real one
/// is what corrects an inflated sense of knowing. It advises, never grades.
class _SelfCheckHint extends StatelessWidget {
  const new({required this.attempted, required this.recall});

  final bool attempted;
  final String recall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!attempted) {
      return Text(
        'No attempt recorded. Grade honestly — a rating you inflate only '
        'delays the next review.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Your answer', style: theme.textTheme.labelSmall),
        const SizedBox(height: 4),
        Text(recall, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Text(
          'Compare the two and grade what actually happened.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const new({
    required this.revealed,
    required this.canReveal,
    required this.previews,
    required this.onReveal,
    required this.onRate,
  });

  final bool revealed;
  final bool canReveal;
  final Map<Rating, String>? previews;
  final VoidCallback onReveal;
  final ValueChanged<Rating> onRate;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: revealed
            ? Row(
                children: <Widget>[
                  for (final rating in Rating.values)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: _RatingButton(
                          rating: rating,
                          preview: previews?[rating],
                          onPressed: () => onRate(rating),
                        ),
                      ),
                    ),
                ],
              )
            : SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: canReveal ? onReveal : null,
                  child: Text(canReveal ? 'Show answer' : 'Answer first'),
                ),
              ),
      ),
    );
  }
}

class _RatingButton extends StatelessWidget {
  const new({required this.rating, required this.onPressed, this.preview});

  final Rating rating;
  final VoidCallback onPressed;

  /// The next interval this rating would schedule, or null before/without
  /// the preview load (the button degrades to label-only).
  final String? preview;

  static const _labels = <Rating, String>{
    Rating.again: 'Again',
    Rating.hard: 'Hard',
    Rating.good: 'Good',
    Rating.easy: 'Easy',
  };

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(_labels[rating]!, textAlign: TextAlign.center),
          if (preview != null)
            Text(preview!, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

/// Post-session summary.
///
/// Stats belong here rather than during review: a running accuracy figure on
/// the review screen invites optimising the number instead of the recall.
class _SessionSummary extends StatelessWidget {
  const new({required this.ratings});

  final List<Rating> ratings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lapses = ratings.where((r) => r == Rating.again).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Session complete')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${ratings.length} reviewed',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            for (final rating in Rating.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 80,
                      child: Text(_RatingButton._labels[rating]!),
                    ),
                    Text('${ratings.where((r) => r == rating).length}'),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            if (lapses == 0 && ratings.isNotEmpty)
              Text(
                'Nothing came back as forgotten. Intervals will stretch.',
                style: theme.textTheme.bodyMedium,
              ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
