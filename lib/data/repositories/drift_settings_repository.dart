import 'package:flashcards2/data/daos/settings_dao.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/domain/entities/scheduling.dart';
import 'package:flashcards2/domain/repositories/settings_repository.dart';

/// Drift-backed [SettingsRepository].
///
/// The id is always forced to the singleton, so callers cannot accidentally
/// create a second settings row even by passing a stray id.
class DriftSettingsRepository implements SettingsRepository {
  new(AppDatabase db) : _dao = SettingsDao(db);

  final SettingsDao _dao;

  @override
  Future<AppSettings> read() async {
    final row = await _dao.readOrCreate();
    return _toDomain(row);
  }

  @override
  Future<void> update(AppSettings settings) async {
    await _dao.updateSettings(
      AppSettingsRow(
        id: AppSettings.singletonId,
        themeMode: settings.themeMode,
        dayCutoffHour: settings.dayCutoffHour,
        memorySpan: settings.memorySpan,
        forcedGenerationBarrier: settings.forcedGenerationBarrier,
        onboardingCompletedAt: settings.onboardingCompletedAt,
        apiBaseUrl: settings.apiBaseUrl,
        apiModelId: settings.apiModelId,
        apiConfiguredAt: settings.apiConfiguredAt,
      ),
    );
  }

  AppSettings _toDomain(AppSettingsRow row) {
    return AppSettings(
      id: row.id,
      themeMode: row.themeMode,
      dayCutoffHour: row.dayCutoffHour,
      memorySpan: row.memorySpan,
      forcedGenerationBarrier: row.forcedGenerationBarrier,
      onboardingCompletedAt: row.onboardingCompletedAt,
      apiBaseUrl: row.apiBaseUrl,
      apiModelId: row.apiModelId,
      apiConfiguredAt: row.apiConfiguredAt,
    );
  }
}
