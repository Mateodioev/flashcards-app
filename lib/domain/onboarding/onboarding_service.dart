import 'package:flashcards2/domain/entities/scheduling.dart';
import 'package:flashcards2/domain/onboarding/onboarding.dart';
import 'package:flashcards2/domain/repositories/settings_repository.dart';

/// Persists onboarding outcomes into the settings row.
///
/// Lives in `domain/` so it depends only on the repository interface, not on
/// Drift — which lets the persistence path be tested without a database.
class OnboardingService {
  const new(this._settings);

  final SettingsRepository _settings;

  /// Writes [result], stamping the completion time.
  ///
  /// Extracts only what belongs in settings: the measured span and the barrier
  /// default. Daily limits are deliberately **not** stored here, because they
  /// are derived from the span and storing both would let the two drift apart.
  Future<AppSettings> apply(
    OnboardingResult result, {
    required DateTime completedAt,
  }) async {
    final current = await _settings.read();
    final updated = AppSettings(
      id: AppSettings.singletonId,
      themeMode: current.themeMode,
      dayCutoffHour: current.dayCutoffHour,
      memorySpan: result.span,
      forcedGenerationBarrier: result.forcedGenerationBarrierDefault,
      onboardingCompletedAt: completedAt,
      apiBaseUrl: current.apiBaseUrl,
      apiModelId: current.apiModelId,
      apiConfiguredAt: current.apiConfiguredAt,
    );
    await _settings.update(updated);
    return updated;
  }

  /// Whether onboarding has ever been completed.
  ///
  /// A skipped run still stamps the time, so the app does not re-prompt on
  /// every launch — skipping is a decision, not an absence of one.
  Future<bool> isComplete() async {
    final settings = await _settings.read();
    return settings.onboardingCompletedAt != null;
  }
}
