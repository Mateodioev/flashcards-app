import 'dart:io';

import 'package:flashcards2/domain/backup/backup.dart';
import 'package:flashcards2/domain/backup/backup_io.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:share_plus/share_plus.dart';

part 'backup_files.g.dart';

/// Moves a backup between the app and the filesystem.
///
/// Separate from [Backup], [BackupExporter] and [BackupImporter], which are
/// pure domain code with no `dart:io`. Keeping the filesystem here means the
/// format and the mapping rules stay testable in memory, and only this thin
/// layer needs a device.
abstract interface class BackupFiles {
  /// Writes [backup] and returns the path it landed at.
  Future<String> write(Backup backup, {DateTime? now});

  /// Reads and parses the backup at [path].
  Future<Backup> read(String path);

  /// Where backups are written, shown to the learner so they can find the file.
  Future<String> defaultDirectory();
}

class FileBackupFiles implements BackupFiles {
  /// Writes into the app's documents directory.
  ///
  /// Documents rather than cache: a cache directory can be cleared by the
  /// system at any time, and a backup the OS deletes when storage runs low is
  /// worse than no backup, because the learner believes they have one.
  @override
  Future<String> defaultDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  @override
  Future<String> write(Backup backup, {DateTime? now}) async {
    final directory = await getApplicationDocumentsDirectory();
    final stamp = _timestamp(now ?? DateTime.now());
    final file = File('${directory.path}/flashcards2-backup-$stamp.json');
    await file.writeAsString(backup.encode(), flush: true);
    return file.path;
  }

  @override
  Future<Backup> read(String path) async {
    final file = File(path);
    // The synchronous check is deliberate: this runs once, on a file the
    // learner just chose, and avoids a second async hop for a trivial stat.
    if (!file.existsSync()) {
      throw BackupFormatException('There is no file at $path.');
    }
    return Backup.decode(await file.readAsString());
  }

  /// A filename-safe local timestamp, so backups sort chronologically and a
  /// second export never overwrites the first.
  static String _timestamp(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${at.year}${two(at.month)}${two(at.day)}'
        '-${two(at.hour)}${two(at.minute)}${two(at.second)}';
  }
}

/// The filesystem bridge, overridden in tests with an in-memory implementation.
@Riverpod(keepAlive: true)
BackupFiles backupFiles(Ref ref) => FileBackupFiles();

/// Hands a written backup to the platform share sheet.
///
/// Kept as an interface because the real implementation only exists behind a
/// platform channel: widget tests would hit `MissingPluginException` without
/// a fake to override, exactly like [BackupFiles] above.
abstract interface class BackupSharer {
  /// Opens the share sheet with the file at [path].
  Future<void> share(String path);
}

class SharePlusBackupSharer implements BackupSharer {
  @override
  Future<void> share(String path) {
    return SharePlus.instance.share(
      ShareParams(files: [XFile(path)]),
    );
  }
}

/// The share bridge, overridden in tests so no platform channel is needed.
@Riverpod(keepAlive: true)
BackupSharer backupSharer(Ref ref) => SharePlusBackupSharer();

/// The exporter, wired to the real repositories.
@Riverpod(keepAlive: true)
BackupExporter backupExporter(Ref ref) => BackupExporter(
  courses: ref.watch(courseRepositoryProvider),
  cards: ref.watch(cardRepositoryProvider),
  logs: ref.watch(reviewLogRepositoryProvider),
  settings: ref.watch(settingsRepositoryProvider),
  reminders: ref.watch(reminderRepositoryProvider),
);

/// The importer, wired to the real repositories.
@Riverpod(keepAlive: true)
BackupImporter backupImporter(Ref ref) => BackupImporter(
  courses: ref.watch(courseRepositoryProvider),
  cards: ref.watch(cardRepositoryProvider),
  logs: ref.watch(reviewLogRepositoryProvider),
  settings: ref.watch(settingsRepositoryProvider),
  reminders: ref.watch(reminderRepositoryProvider),
);
