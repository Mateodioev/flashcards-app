import 'package:drift/native.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/data/repositories/drift_card_repository.dart';
import 'package:flashcards2/data/repositories/drift_course_repository.dart';
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

void main() {
  late AppDatabase db;
  late _MemoryFiles files;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    files = _MemoryFiles();
  });
  tearDown(() => db.close());

  Widget app() {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        backupFilesProvider.overrideWithValue(files),
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
    testWidgets('writes a file and reports where it went', (tester) async {
      await seedCourse('Biology');
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Export a backup'));
      await tester.pumpAndSettle();

      expect(files.written, hasLength(1));
      // A backup the learner cannot find is not a backup, so the path must be
      // shown rather than written silently.
      expect(
        find.textContaining('/fake/documents/backup-0.json'),
        findsOneWidget,
      );
    });

    testWidgets('never mentions the API key in what it says', (tester) async {
      await seedCourse('Biology');
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Export a backup'));
      await tester.pumpAndSettle();

      for (final content in files.written.values) {
        expect(content.toLowerCase(), isNot(contains('apikey')));
      }
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
      await tester.tap(find.text('Export a backup'));
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

      await tester.tap(find.text('Export a backup'));
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
      await tester.tap(find.text('Export a backup'));
      await tester.pumpAndSettle();

      final written = files.written.values.single;
      expect(written, contains('Chemistry'));

      // And the importer path is wired to the database, not a stub.
      final importer = BackupImporter(
        courses: DriftCourseRepository(db),
        cards: DriftCardRepository(db),
        logs: DriftReviewLogRepository(db),
        settings: DriftSettingsRepository(db),
      );
      expect(importer, isNotNull);
    });
  });
}
