import 'package:flashcards2/domain/entities/course.dart';
import 'package:flashcards2/domain/entities/theme.dart' as domain;
import 'package:flashcards2/domain/reminders/reminder.dart';
import 'package:flashcards2/domain/reminders/reminder_payload.dart';
import 'package:flashcards2/domain/repositories/card_repository.dart';
import 'package:flashcards2/domain/repositories/course_repository.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flashcards2/presentation/study_session_launcher.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a reminder tap resolves into: a global session has neither target,
/// a course session has only `course`, a theme session carries both —
/// exactly the argument shapes `study_session_launcher.dart` takes.
typedef ReminderRoute = ({
  ReminderScope scope,
  Course? course,
  domain.Theme? theme,
});

/// Turns the OS-delivered payload (untrusted bytes) into launcher arguments.
/// Returns null for malformed payloads and for targets that vanished after
/// scheduling — the S13 cascade is the real guard, this is the last defense,
/// and either way a tap must never crash the app (plan §3.4).
Future<ReminderRoute?> resolveReminderRoute(
  String payload, {
  required CourseRepository courses,
  required CardRepository cards,
}) async {
  final intent = decodeReminderPayload(payload);
  if (intent == null) return null;

  switch (intent.scope) {
    case ReminderScope.global:
      return (scope: ReminderScope.global, course: null, theme: null);
    case ReminderScope.course:
      final course = await courses.findById(intent.targetId ?? -1);
      if (course == null) return null;
      return (scope: ReminderScope.course, course: course, theme: null);
    case ReminderScope.theme:
      final theme = await cards.findThemeById(intent.targetId ?? -1);
      if (theme == null) return null;
      final course = await courses.findById(theme.courseId);
      if (course == null) return null;
      return (scope: ReminderScope.theme, course: course, theme: theme);
  }
}

/// Polls briefly for the root navigator. The plan (§3.4, T7) requires tap
/// routing to wait for the onboarding-gated `MaterialApp` to exist; a
/// cold-start tap can otherwise arrive before the first frame is built.
Future<BuildContext?> waitForNavigatorContext(
  GlobalKey<NavigatorState> navigatorKey, {
  Duration interval = const Duration(milliseconds: 50),
  int maxAttempts = 20,
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final context = navigatorKey.currentContext;
    if (context != null && context.mounted) return context;
    await Future<void>.delayed(interval);
  }
  return null;
}

/// Full tap path (S11): decode → resolve → wait for the gate → launch the
/// study session for the payload's scope through the same launcher used by
/// the course list, so behavior (empty-state SnackBar included) is identical.
Future<void> routeReminderPayload(
  String payload, {
  required GlobalKey<NavigatorState> navigatorKey,
  required WidgetRef ref,
}) async {
  final route = await resolveReminderRoute(
    payload,
    courses: ref.read(courseRepositoryProvider),
    cards: ref.read(cardRepositoryProvider),
  );
  if (route == null) return;

  final context = await waitForNavigatorContext(navigatorKey);
  // waitForNavigatorContext only returns mounted contexts; mounted is
  // reasserted because the lint cannot see through the await.
  if (context == null || !context.mounted) return;

  final course = route.course;
  if (course == null) {
    await startGlobalStudySession(context: context, ref: ref);
  } else {
    await startStudySession(
      context: context,
      ref: ref,
      course: course,
      theme: route.theme,
    );
  }
}
