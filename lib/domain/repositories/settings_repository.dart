import 'package:flashcards2/domain/entities/scheduling.dart';

/// Persistence boundary for the single-row settings table.
abstract interface class SettingsRepository {
  /// Reads the settings row, creating it with defaults if it is absent.
  Future<AppSettings> read();

  Future<void> update(AppSettings settings);
}
