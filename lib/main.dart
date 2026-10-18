import 'package:flashcards2/core/theme.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/data/notifications/reminder_time_zone.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flashcards2/presentation/screens/course_list_screen.dart';
import 'package:flashcards2/presentation/screens/onboarding_screen.dart';
import 'package:flashcards2/presentation/study_reminder_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Root navigator handle (plan §3.4/T7): reminder taps route through it,
/// deferred until the onboarding-gated home exists.
final rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  // TZDateTime scheduling needs the zone database ready before the first
  // reminder is scheduled; doing it before runApp keeps the gateway simple.
  WidgetsFlutterBinding.ensureInitialized();
  await initReminderTimeZone();
  runApp(
    ProviderScope(
      overrides: [
        // The only place the on-disk database is constructed. Everything else
        // depends on the provider, which tests swap for an in-memory instance.
        databaseProvider.overrideWithValue(AppDatabase()),
      ],
      child: const FlashcardsApp(),
    ),
  );
}

/// Root of the application.
///
/// Watchful rather than stateless because the theme mode is persisted: changing
/// it in settings must re-render the whole app without a restart.
class FlashcardsApp extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<FlashcardsApp> createState() => _FlashcardsAppState();
}

class _FlashcardsAppState extends ConsumerState<FlashcardsApp> {
  @override
  void initState() {
    super.initState();
    // Plan §1 + §3.4: wire the reminder tap handler BEFORE reconciling on
    // every app start — the handler also delivers the cold-start payload via
    // the gateway's launch-details check. Errors are swallowed here exactly
    // like the onboarding gate below: a scheduling failure must never lock
    // the learner out.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(notificationGatewayProvider).initialize(
          onReminderTap: (payload) => routeReminderPayload(
            payload,
            navigatorKey: rootNavigatorKey,
            ref: ref,
          ),
        );
        await ref.read(reminderRescheduleProvider)();
      } on Object catch (_) {
        // Best effort; the next save or app start reconciles again.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeModeProvider);
    final settings = ref.watch(appSettingsProvider);

    return MaterialApp(
      title: 'Flashcards',
      navigatorKey: rootNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: mode,
      // First launch runs the onboarding audit; when it completes (or is
      // skipped) the settings row gets its stamp and this gate flips by
      // itself. A settings error must never lock the learner out, so it
      // falls through to the course list.
      home: settings.when(
        data: (value) => value.onboardingCompletedAt == null
            ? const OnboardingScreen()
            : const CourseListScreen(),
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => const CourseListScreen(),
      ),
    );
  }
}
