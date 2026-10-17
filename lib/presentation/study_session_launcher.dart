import 'package:flashcards2/domain/entities/course.dart';
import 'package:flashcards2/domain/entities/theme.dart' as domain;
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
          SchedulerConfig(dayCutoffHour: settings.dayCutoffHour),
        ),
        barrierEnabled: settings.forcedGenerationBarrier,
      ),
    ),
  );

  if (theme != null) {
    ref.invalidate(cardsProvider(theme.id));
  }
}
