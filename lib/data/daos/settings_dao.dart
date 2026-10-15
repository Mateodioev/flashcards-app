import 'package:drift/drift.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/data/tables/tables.dart';

part 'settings_dao.g.dart';

/// Access to the single-row `app_settings` table.
///
/// The CHECK constraint pins the id to `1`, so [readOrCreate] is the only
/// sensible way in: it inserts the default row on first use and returns it
/// thereafter.
@DriftAccessor(tables: [AppSettings])
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  new(super.attachedDatabase);

  /// The id of the only settings row there can be.
  static const int singletonId = 1;

  Future<AppSettingsRow?> read() {
    return (select(
      appSettings,
    )..where((t) => t.id.equals(singletonId))).getSingleOrNull();
  }

  Stream<AppSettingsRow?> watch() {
    return (select(
      appSettings,
    )..where((t) => t.id.equals(singletonId))).watchSingleOrNull();
  }

  /// Reads the settings row, inserting the default row if it does not exist.
  Future<AppSettingsRow> readOrCreate() async {
    final existing = await read();
    if (existing != null) {
      return existing;
    }

    return await into(appSettings)
        .insertReturning(const AppSettingsCompanion(id: Value(singletonId)));
  }

  Future<bool> updateSettings(AppSettingsRow settings) {
    return update(appSettings).replace(settings);
  }
}
