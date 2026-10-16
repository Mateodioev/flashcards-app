import 'package:drift/native.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/domain/onboarding/memory_span.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flashcards2/presentation/screens/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The onboarding audit end to end against a real in-memory database.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// Fast reveals keep the widget tests quick; the seed makes the digit
  /// sequences reproducible, so the test can mirror the real session.
  Widget app({required int seed}) {
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: OnboardingScreen(
          seed: seed,
          perDigit: const Duration(milliseconds: 5),
        ),
      ),
    );
  }

  /// Every wrong response: each digit shifted by one, so no position is ever
  /// right and the calibration input is deterministic (bias = prediction).
  List<int> shifted(MemorySpanTrial trial) {
    return [for (final d in trial.digits) if (d == 9) 1 else d + 1];
  }

  /// Plays one trial on the screen and mirrors it in [reference], so both
  /// sessions advance identically and the test knows when the game is over.
  Future<void> playTrial(
    WidgetTester tester,
    MemorySpanSession reference,
    List<int> response,
  ) async {
    await tester.tap(find.text('100%'));
    await tester.pumpAndSettle();
    for (final digit in response) {
      await tester.tap(find.text('$digit'));
      // A frame per tap, as on a real device — otherwise Check is hit-tested
      // against the stale frame where it was still disabled.
      await tester.pump();
    }
    await tester.tap(find.text('Check'));
    await tester.pumpAndSettle();
    reference.submit(response);
  }

  Future<void> beginSession(WidgetTester tester, int seed) async {
    await tester.pumpWidget(app(seed: seed));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Begin'));
    await tester.pumpAndSettle();
  }

  testWidgets('skip stamps completion and applies the documented defaults', (
    tester,
  ) async {
    await tester.pumpWidget(app(seed: 7));
    await tester.pumpAndSettle();

    expect(find.text('Two-minute setup'), findsOneWidget);

    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    final row = await db.select(db.appSettings).getSingle();
    expect(
      row.onboardingCompletedAt,
      isNotNull,
      reason: 'skipping is a decision, not an absence of one',
    );
    expect(
      row.memorySpan,
      4,
      reason: 'skipped onboarding writes the fallback span, never a null',
    );
    expect(row.forcedGenerationBarrier, isFalse);
  });

  testWidgets('a perfect run measures the span and persists it', (
    tester,
  ) async {
    const seed = 7;
    final reference = MemorySpanSession(seed: seed);

    await beginSession(tester, seed);
    while (!reference.isComplete) {
      final trial = reference.current;
      await playTrial(tester, reference, List<int>.of(trial.digits));
    }

    expect(find.text('All set'), findsOneWidget);
    expect(find.text('9 items'), findsOneWidget);

    await tester.tap(find.text('Start learning'));
    await tester.pumpAndSettle();

    final row = await db.select(db.appSettings).getSingle();
    expect(row.memorySpan, 9);
    expect(row.onboardingCompletedAt, isNotNull);
    expect(
      row.forcedGenerationBarrier,
      isFalse,
      reason: 'predicted 100% and scored 100% — calibrated, barrier stays off',
    );
  });

  testWidgets('predictions ahead of recall turn the barrier on', (
    tester,
  ) async {
    const seed = 3;
    final reference = MemorySpanSession(seed: seed);

    await beginSession(tester, seed);
    while (!reference.isComplete) {
      final trial = reference.current;
      // Pass until length 6, then fail both attempts: bias 0 on passes, +1 on
      // failures, mean 0.4 — overconfident.
      final pass = trial.length < 6;
      await playTrial(
        tester,
        reference,
        pass ? List<int>.of(trial.digits) : shifted(trial),
      );
    }

    expect(find.text('All set'), findsOneWidget);
    expect(find.text('5 items'), findsOneWidget);

    await tester.tap(find.text('Start learning'));
    await tester.pumpAndSettle();

    final row = await db.select(db.appSettings).getSingle();
    expect(row.memorySpan, 5);
    expect(
      row.forcedGenerationBarrier,
      isTrue,
      reason: 'overconfidence turns the recall barrier on',
    );
  });

  testWidgets('failing everything falls back to the default span, honestly', (
    tester,
  ) async {
    const seed = 3;
    final reference = MemorySpanSession(seed: seed);

    await beginSession(tester, seed);
    while (!reference.isComplete) {
      final trial = reference.current;
      await playTrial(tester, reference, shifted(trial));
    }

    expect(find.text('Default — 4 items'), findsOneWidget);
    expect(
      find.text(
        'Not enough trials to judge calibration, so the recall barrier stays '
        'off.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Start learning'));
    await tester.pumpAndSettle();

    final row = await db.select(db.appSettings).getSingle();
    expect(row.memorySpan, 4);
    expect(row.forcedGenerationBarrier, isFalse);
  });

  testWidgets('a rerun from settings pops back after finishing', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const OnboardingScreen(isRerun: true),
                  ),
                ),
                child: const Text('open onboarding'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open onboarding'));
    await tester.pumpAndSettle();
    expect(find.text('Two-minute setup'), findsOneWidget);

    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingScreen), findsNothing);
  });
}
