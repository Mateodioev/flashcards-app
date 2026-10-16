import 'dart:async';
import 'dart:math';

import 'package:flashcards2/domain/onboarding/calibration.dart';
import 'package:flashcards2/domain/onboarding/memory_span.dart';
import 'package:flashcards2/domain/onboarding/onboarding.dart';
import 'package:flashcards2/domain/onboarding/onboarding_service.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The first-run audit: a short digit-span game that measures working memory,
/// with a confidence question before every trial that feeds the calibration
/// probe. Skippable, and re-runnable from settings.
///
/// All the logic lives in the domain (`MemorySpanSession`, `CalibrationProbe`,
/// `Onboarding`); this screen only drives it and persists the result through
/// [OnboardingService]. Skipping applies the documented defaults — never
/// nulls — and still stamps the completion time, because skipping is a
/// decision, not an absence of one.
class OnboardingScreen extends ConsumerStatefulWidget {
  const new({
    super.key,
    this.isRerun = false,
    this.seed,
    this.perDigit = const Duration(milliseconds: 900),
  });

  /// True when pushed from settings to run the audit again: finishing pops
  /// back instead of relying on the launch gate to swap the home screen.
  final bool isRerun;

  /// Session seed. Production passes null and gets a random session; tests
  /// pass a fixed seed so the digit sequences are reproducible.
  final int? seed;

  /// How long each digit stays visible in the reveal phase.
  final Duration perDigit;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _Step { welcome, trial, result }

enum _TrialPhase { predict, show, recall }

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  _Step _step = _Step.welcome;
  _TrialPhase _phase = _TrialPhase.predict;

  late MemorySpanSession _session;
  CalibrationProbe _probe = const CalibrationProbe();
  late OnboardingResult _result;
  bool _usedFallback = false;

  final List<int> _entry = <int>[];
  double? _predicted;
  String _feedback = '';
  bool _finishing = false;
  Timer? _revealTimer;

  MemorySpanTrial get _trial => _session.current;

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  void _begin() {
    _session = MemorySpanSession(
      seed: widget.seed ?? Random().nextInt(1 << 30),
    );
    setState(() {
      _step = _Step.trial;
      _phase = _TrialPhase.predict;
    });
  }

  /// The prediction is the calibration input: asking before the trial, not
  /// after, is what separates a judgement from a post-hoc rationalisation.
  void _selectPrediction(double value) {
    if (_phase != _TrialPhase.predict) return;
    _predicted = value;
    setState(() => _phase = _TrialPhase.show);
    _revealTimer = Timer(widget.perDigit * _trial.length, () {
      if (mounted) setState(() => _phase = _TrialPhase.recall);
    });
  }

  void _tapDigit(int digit) {
    if (_phase != _TrialPhase.recall) return;
    if (_entry.length >= _trial.length) return;
    setState(() => _entry.add(digit));
  }

  void _backspace() {
    if (_entry.isEmpty) return;
    setState(_entry.removeLast);
  }

  void _check() {
    final trial = _trial;
    if (_entry.length != trial.length) return;

    // Partial accuracy (positions right) is the calibration's "actual"; the
    // span session itself stays strict — order matters, all or nothing.
    var correctPositions = 0;
    for (var i = 0; i < trial.length; i++) {
      if (_entry[i] == trial.digits[i]) correctPositions++;
    }
    final predicted = _predicted;
    if (predicted != null) {
      _probe = _probe.withTrial(
        CalibrationTrial(
          predicted: predicted,
          actual: correctPositions / trial.length,
        ),
      );
    }

    final passed = trial.isCorrect(_entry);
    _session.submit(List<int>.of(_entry));
    _entry.clear();
    _predicted = null;

    if (_session.isComplete) {
      _usedFallback = _session.outcome.span <= 0;
      _result = Onboarding.combine(
        spanOutcome: _session.outcome,
        calibration: _probe.result,
      );
      setState(() => _step = _Step.result);
      return;
    }

    setState(() {
      _feedback = passed
          ? 'Correct — next: ${_trial.length} digits.'
          : 'Not quite — trying ${_trial.length} again.';
      _phase = _TrialPhase.predict;
    });
  }

  Future<void> _apply(OnboardingResult result) async {
    setState(() => _finishing = true);
    await ref
        .read(onboardingServiceProvider)
        .apply(result, completedAt: DateTime.now());
    ref.invalidate(appSettingsProvider);
    // First run: invalidating settings flips the launch gate by itself. A
    // rerun was pushed on the navigator, so it pops back to settings.
    if (widget.isRerun && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _skip() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Skip setup?'),
        content: const Text(
          'Sensible defaults apply (span 4, barrier off). You can run this '
          'anytime from Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Skip'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await _apply(OnboardingResult.skipped());
    }
  }

  Future<void> _finish() => _apply(_result);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup'),
        actions: [
          if (_step != _Step.result)
            TextButton(
              onPressed: _finishing ? null : _skip,
              child: const Text('Skip for now'),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: switch (_step) {
            _Step.welcome => _buildWelcome(context),
            _Step.trial => _buildTrial(context),
            _Step.result => _buildResult(context),
          },
        ),
      ),
    );
  }

  Widget _buildWelcome(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        Text(
          'Two-minute setup',
          style: theme.textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          'A short digit game measures your working-memory span, and before '
          'each round you predict how you will do. Together they set how many '
          'new cards you get per day. Nothing leaves your device.',
          style: theme.textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const Spacer(),
        FilledButton(onPressed: _begin, child: const Text('Begin')),
      ],
    );
  }

  Widget _buildTrial(BuildContext context) {
    final theme = Theme.of(context);
    final trial = _trial;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_feedback.isNotEmpty) ...[
          Text(
            _feedback,
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
        ],
        Text(
          'Remember ${trial.length} digits, in order',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        Expanded(
          child: Center(
            child: switch (_phase) {
              _TrialPhase.predict => _buildPredict(),
              _TrialPhase.show => Text(
                  trial.digits.join(' '),
                  style: theme.textTheme.displayMedium,
                ),
              _TrialPhase.recall => _buildRecall(trial),
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPredict() {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'How much of it will you recall?',
          style: theme.textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final option in const [0.0, 0.25, 0.5, 0.75, 1.0])
              ChoiceChip(
                label: Text('${(option * 100).round()}%'),
                selected: false,
                onSelected: (_) => _selectPrediction(option),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecall(MemorySpanTrial trial) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          // Placeholders keep the width stable and, unlike a bare digit,
          // never collide with the keypad labels in tests or semantics.
          [
            for (var i = 0; i < trial.length; i++)
              if (i < _entry.length) '${_entry[i]}' else '·',
          ].join(' '),
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: 24),
        SizedBox(
          // Fixed width keeps the keypad compact on tablets instead of
          // stretching tiles into giant buttons that push Check off-screen.
          width: 320,
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.8,
            children: [
            for (final digit in const [1, 2, 3, 4, 5, 6, 7, 8, 9])
              OutlinedButton(
                onPressed: () => _tapDigit(digit),
                child: Text('$digit'),
              ),
            IconButton.filledTonal(
              onPressed: _backspace,
              icon: const Icon(Icons.backspace_outlined),
            ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _entry.length == trial.length && !_finishing
              ? _check
              : null,
          child: const Text('Check'),
        ),
      ],
    );
  }

  Widget _buildResult(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;

    final verdict = switch (result.calibrationVerdict) {
      CalibrationVerdict.overconfident =>
        'Your predictions ran ahead of your recall. The recall barrier starts '
            'on: you will attempt the answer before it is revealed.',
      CalibrationVerdict.calibrated =>
        'Your predictions matched your recall closely.',
      CalibrationVerdict.underconfident =>
        'You recalled more than you expected — trust your memory a little '
            'more.',
      CalibrationVerdict.insufficient =>
        'Not enough trials to judge calibration, so the recall barrier stays '
            'off.',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'All set',
          style: theme.textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        ListTile(
          title: const Text('Memory span'),
          subtitle: Text(
            _usedFallback
                ? 'Default — ${result.span} items'
                : '${result.span} items',
          ),
        ),
        ListTile(
          title: const Text('New cards per day'),
          subtitle: Text('${result.newCardsPerDay}'),
        ),
        const SizedBox(height: 8),
        Text(verdict, style: theme.textTheme.bodyLarge),
        const Spacer(),
        FilledButton(
          onPressed: _finishing ? null : _finish,
          child: Text(widget.isRerun ? 'Save' : 'Start learning'),
        ),
      ],
    );
  }
}
