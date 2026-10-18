import 'dart:math' as math;

import 'package:flashcards2/domain/entities/course.dart';
import 'package:flashcards2/domain/entities/theme.dart' as domain;
import 'package:flashcards2/domain/onboarding/memory_span.dart';
import 'package:flashcards2/domain/scheduling/fsrs6_adapter.dart';
import 'package:flashcards2/domain/scheduling/global_session.dart';
import 'package:flashcards2/domain/scheduling/scheduler.dart';
import 'package:flashcards2/domain/scheduling/session.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flashcards2/presentation/screens/review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Builds and opens one study session.
///
/// [theme] scopes the session to a single theme; when null the session spans
/// the whole [course]. The new-card allowance is always the course's business:
/// cards introduced in *any* of the course's themes today count against the
/// course's daily cap, because the cap lives on the course, not the theme.
Future<void> startStudySession({
  required BuildContext context,
  required WidgetRef ref,
  required Course course,
  domain.Theme? theme,
}) async {
  final cardRepository = ref.read(cardRepositoryProvider);
  final now = DateTime.now();
  final settings = await ref.read(settingsRepositoryProvider).read();

  final due = await cardRepository.findDueEntries(
    dueBefore: now,
    courseId: course.id,
    themeId: theme?.id,
  );
  final fresh = await cardRepository.findNewEntries(
    courseId: course.id,
    themeId: theme?.id,
  );

  // Count across the whole course so the daily cap is genuinely per course,
  // even when the learner opens a single theme.
  final alreadyToday = await ref
      .read(reviewLogRepositoryProvider)
      .countNewCardsIntroducedToday(
        now: now,
        dayCutoffHour: settings.dayCutoffHour,
        courseId: course.id,
      );

  final session = SessionBuilder.build(
    request: SessionRequest(
      now: now,
      courseId: course.id,
      themeId: theme?.id,
      interleaveMode: course.interleaveMode,
      newCardsPerDay: course.newCardsPerDay,
      newCardsAlreadyToday: alreadyToday,
    ),
    due: due,
    fresh: fresh,
  );

  if (!context.mounted) return;

  if (session.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Nothing to study here yet.')));
    return;
  }

  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ReviewScreen(
        items: session.items,
        scheduler: Scheduler(
          SchedulerConfig(
            dayCutoffHour: settings.dayCutoffHour,
            // Production composition root: Anki-compatible interval fuzzing
            // is ON here (the library default is fuzz-OFF, deterministic,
            // for tests). docs/fsrs6_migration_plan.md Phase 2 decision 5.
            memoryEngine: Fsrs6SchedulerAdapter(),
          ),
        ),
        barrierEnabled: settings.forcedGenerationBarrier,
      ),
    ),
  );

  if (theme != null) {
    ref.invalidate(cardsProvider(theme.id));
  }
}

/// Builds and opens one session spanning every non-archived course.
///
/// Policy stays per course (each course's interleave mode and intake cap), and
/// a global ceiling derived from the working-memory span bounds total new-card
/// intake so a wide account cannot flood a session with new material.
Future<void> startGlobalStudySession({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final cardRepository = ref.read(cardRepositoryProvider);
  final courseRepository = ref.read(courseRepositoryProvider);
  final reviewLogRepository = ref.read(reviewLogRepositoryProvider);
  final now = DateTime.now();
  final settings = await ref.read(settingsRepositoryProvider).read();

  final courses = await courseRepository.findAll();
  final alreadyToday = await reviewLogRepository
      .countNewCardsIntroducedTodayByCourse(
        now: now,
        dayCutoffHour: settings.dayCutoffHour,
      );

  // The global queue must not surface archived courses. `findAll` already
  // defaults to non-archived, but the filter is explicit here so the contract
  // does not silently depend on that default.
  final policies = <CourseStudyPolicy>[
    for (final course in courses.where((course) => !course.archived))
      CourseStudyPolicy(
        courseId: course.id,
        interleaveMode: course.interleaveMode,
        newCardsPerDay: course.newCardsPerDay,
        newCardsAlreadyToday: alreadyToday[course.id] ?? 0,
      ),
  ];

  // The global ceiling is daily: it caps the total new cards introduced across
  // every course today, so it must subtract what today has already introduced
  // — the same "daily, not per-session" semantics the per-course allowances
  // already carry.
  final span = settings.memorySpan ?? MemorySpanDefaults.fallbackSpan;
  final dailyCeiling = MemorySpanDefaults.newCardsPerDay(span);
  final totalAlreadyToday = alreadyToday.values.fold<int>(
    0,
    (sum, c) => sum + c,
  );
  final globalCeiling = math.max(0, dailyCeiling - totalAlreadyToday);

  final due = await cardRepository.findDueEntries(dueBefore: now);
  final fresh = await cardRepository.findNewEntries();

  final session = GlobalSessionBuilder.build(
    request: GlobalSessionRequest(
      policies: policies,
      globalNewCardCeiling: globalCeiling,
    ),
    due: due,
    fresh: fresh,
  );

  if (!context.mounted) return;

  if (session.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Nothing to study here yet.')));
    return;
  }

  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ReviewScreen(
        items: session.items,
        scheduler: Scheduler(
          SchedulerConfig(
            dayCutoffHour: settings.dayCutoffHour,
            // See the identical note in startCourseStudySession: production
            // runs the FSRS-6 adapter with fuzzing ON.
            memoryEngine: Fsrs6SchedulerAdapter(),
          ),
        ),
        barrierEnabled: settings.forcedGenerationBarrier,
      ),
    ),
  );

  // Study changed schedule state across many courses; refresh the main course
  // list so any progress/due surface it gains cannot stay stale.
  ref.invalidate(coursesProvider);
}
