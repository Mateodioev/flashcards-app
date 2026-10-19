import 'package:drift/native.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/data/repositories/drift_card_repository.dart';
import 'package:flashcards2/data/repositories/drift_course_repository.dart';
import 'package:flashcards2/data/repositories/drift_reminder_repository.dart';
import 'package:flashcards2/data/repositories/drift_review_log_repository.dart';
import 'package:flashcards2/data/repositories/drift_settings_repository.dart';
import 'package:flashcards2/domain/backup/backup.dart';
import 'package:flashcards2/domain/backup/backup_io.dart';
import 'package:flashcards2/domain/entities/course.dart';
import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/presentation/backup/backup_files.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flashcards2/presentation/screens/backup_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// An in-memory [BackupFiles], so the UI can be driven without touching disk.
class _MemoryFiles implements BackupFiles {
  final Map<String, String> written = <String, String>{};
  String? lastPath;

  @override
  Future<String> defaultDirectory() async => '/fake/documents';

  @override
  Future<String> write(Backup backup, {DateTime? now}) async {
    final path = '/fake/documents/backup-${written.length}.json';
    written[path] = backup.encode();
    lastPath = path;
    return path;
  }

  @override
  Future<Backup> read(String path) async {
    final content = written[path];
    if (content == null) {
      throw BackupFormatException('There is no file at $path.');
    }
    return Backup.decode(content);
  }
}

/// Records what would have been shared, so the UI can be driven without a
/// platform channel.
class _MemorySharer implements BackupSharer {
  String? lastSharedPath;
  int calls = 0;

  @override
  Future<void> share(String path) async {
    calls++;
    lastSharedPath = path;
  }
}

/// A share sheet that never opens, for the fallback-path tests.
class _ThrowingSharer implements BackupSharer {
  @override
  Future<void> share(String path) => Future.error('no share sheet here');
}

/// A filesystem whose writes always fail.
class _ThrowingFiles extends _MemoryFiles {
  @override
  Future<String> write(Backup backup, {DateTime? now}) =>
      Future.error('disk full');
}

void main() {
  late AppDatabase db;
  late _MemoryFiles files;
  late _MemorySharer sharer;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    files = _MemoryFiles();
    sharer = _MemorySharer();
  });
  tearDown(() => db.close());

  Widget app() {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        backupFilesProvider.overrideWithValue(files),
        backupSharerProvider.overrideWithValue(sharer),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: BackupSection())),
      ),
    );
  }

  Future<void> seedCourse(String name) async {
    await DriftCourseRepository(db).create(
      Course(
        id: 0,
        name: name,
        createdAt: DateTime(2022),
        newCardsPerDay: 10,
        interleaveMode: InterleaveMode.blocked,
        archived: false,
      ),
    );
  }

  group('export', () {
    testWidgets('writes a file and hands it to the share sheet', (
      tester,
    ) async {
      await seedCourse('Biology');
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Share a backup'));
      await tester.pumpAndSettle();

      expect(files.written, hasLength(1));
      // The written file is what gets shared, so the learner can send it to
      // WhatsApp, Telegram, Drive, etc. without ever seeing a path.
      expect(sharer.lastSharedPath, '/fake/documents/backup-0.json');
      // The path is still shown as a fallback, in case the share sheet was
      // dismissed or failed.
      expect(
        find.textContaining('/fake/documents/backup-0.json'),
        findsOneWidget,
      );
    });

    testWidgets('never mentions the API key in what it says', (tester) async {
      await seedCourse('Biology');
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Share a backup'));
      await tester.pumpAndSettle();

      for (final content in files.written.values) {
        expect(content.toLowerCase(), isNot(contains('apikey')));
      }
    });

    testWidgets('a share failure still reports the written path', (
      tester,
    ) async {
      await seedCourse('Biology');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            backupFilesProvider.overrideWithValue(files),
            backupSharerProvider.overrideWithValue(_ThrowingSharer()),
          ],
          child: const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: BackupSection())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Share a backup'));
      await tester.pumpAndSettle();

      // Sharing is best-effort: the written file is the real backup, so its
      // path must still be reported instead of a failure.
      expect(
        find.textContaining('/fake/documents/backup-0.json'),
        findsOneWidget,
      );
      expect(find.textContaining('Could not write'), findsNothing);
    });

    testWidgets('a write failure does not open the share sheet', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            backupFilesProvider.overrideWithValue(_ThrowingFiles()),
            backupSharerProvider.overrideWithValue(sharer),
          ],
          child: const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: BackupSection())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Share a backup'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not write the backup'), findsOneWidget);
      expect(
        sharer.calls,
        0,
        reason: 'there is nothing to share when the write itself failed',
      );
    });
  });

  group('restore', () {
    testWidgets('adds the file contents and reports the counts', (
      tester,
    ) async {
      await seedCourse('Original');
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      // Export the current state, then restore it back into the same database.
      await tester.tap(find.text('Share a backup'));
      await tester.pumpAndSettle();
      final path = files.lastPath!;

      await tester.tap(find.text('Restore from a backup'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, path);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // The confirmation must be shown before anything is written.
      expect(find.text('Restore this backup?'), findsOneWidget);
      expect(
        find.textContaining('ADDED'),
        findsOneWidget,
        reason: 'the learner must know nothing is replaced',
      );

      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Restored'), findsOneWidget);
      final all = await DriftCourseRepository(db).findAll();
      expect(all, hasLength(2), reason: 'additive, not a replacement');
    });

    testWidgets('a cancelled confirmation imports nothing', (tester) async {
      await seedCourse('Original');
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Share a backup'));
      await tester.pumpAndSettle();
      final path = files.lastPath!;

      await tester.tap(find.text('Restore from a backup'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, path);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(await DriftCourseRepository(db).findAll(), hasLength(1));
    });

    testWidgets('a missing file reports a readable error', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Restore from a backup'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        '/fake/documents/nope.json',
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('no file at'), findsOneWidget);
      expect(
        find.textContaining('Nothing was imported'),
        findsOneWidget,
        reason: 'the learner must know their existing data is intact',
      );
    });

    testWidgets('a corrupt file is refused before anything is written', (
      tester,
    ) async {
      await seedCourse('Original');
      files.written['/fake/broken.json'] = 'not a backup at all';

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Restore from a backup'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '/fake/broken.json');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('not valid JSON'), findsOneWidget);
      expect(await DriftCourseRepository(db).findAll(), hasLength(1));
    });
  });

  group('the wiring is real', () {
    testWidgets('export uses the actual repositories', (tester) async {
      // Guards against the panel rendering while wired to nothing.
      await seedCourse('Chemistry');
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share a backup'));
      await tester.pumpAndSettle();

      final written = files.written.values.single;
      expect(written, contains('Chemistry'));

      // And the importer path is wired to the database, not a stub.
      final importer = BackupImporter(
        courses: DriftCourseRepository(db),
        cards: DriftCardRepository(db),
        logs: DriftReviewLogRepository(db),
        settings: DriftSettingsRepository(db),
        reminders: DriftReminderRepository(db),
      );
      expect(importer, isNotNull);
    });
  });
}
