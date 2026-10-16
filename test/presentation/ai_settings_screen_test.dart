import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flashcards2/data/ai/openai_compatible_client.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flashcards2/presentation/screens/ai_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late InMemoryApiKeyStore keys;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    keys = InMemoryApiKeyStore();
  });
  tearDown(() => db.close());

  Widget app() {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        apiKeyStoreProvider.overrideWithValue(keys),
      ],
      child: const MaterialApp(home: AiSettingsScreen()),
    );
  }

  /// Seed the settings row directly, the way a previous session would have.
  Future<void> seed({
    String? baseUrl,
    String? modelId,
    DateTime? configuredAt,
  }) {
    return db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            id: const Value(1),
            apiBaseUrl: Value(baseUrl),
            apiModelId: Value(modelId),
            apiConfiguredAt: Value(configuredAt),
          ),
        );
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
  }

  group('the stored key is never rendered', () {
    testWidgets('with a stored key the field is not shown at all', (
      tester,
    ) async {
      await keys.write('stored-secret-key-xyz');
      await seed(baseUrl: 'https://example.test/v1', modelId: 'm');

      await tester.pumpWidget(app());
      await settle(tester);

      expect(
        find.text('stored-secret-key-xyz'),
        findsNothing,
        reason:
            'the whole point of secure storage is that the UI never '
            'paints the secret back out',
      );
      expect(find.text('A key is stored'), findsOneWidget);
      expect(find.text('Replace'), findsOneWidget);
    });

    testWidgets('the key field appears when nothing is stored', (tester) async {
      await tester.pumpWidget(app());
      await settle(tester);

      expect(find.text('A key is stored'), findsNothing);
      expect(find.text('API key'), findsOneWidget);
    });

    testWidgets('Replace reveals an empty field, not the stored value', (
      tester,
    ) async {
      await keys.write('stored-secret-key-xyz');
      await tester.pumpWidget(app());
      await settle(tester);

      await tester.tap(find.text('Replace'));
      await settle(tester);

      final field = find.byType(TextField).last;
      expect(
        tester.widget<TextField>(field).controller?.text ?? '',
        isEmpty,
        reason: 'replacing must start blank, not from the stored secret',
      );
      expect(find.text('stored-secret-key-xyz'), findsNothing);
    });
  });

  group('honest disabled state', () {
    testWidgets('says the feature is disabled with no configuration', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await settle(tester);

      expect(
        find.textContaining('disabled until a key is stored'),
        findsOneWidget,
      );
    });

    testWidgets('a model alone is not enough to enable it', (tester) async {
      // The DB can hold a model while no key exists, because the key lives
      // outside it. Claiming "enabled" from the row alone would be a lie.
      await seed(baseUrl: 'https://example.test/v1', modelId: 'vision-model');

      await tester.pumpWidget(app());
      await settle(tester);

      expect(
        find.textContaining('disabled until a key is stored'),
        findsOneWidget,
        reason: 'a stored model without a key cannot work',
      );
    });

    testWidgets('shows the stored model id', (tester) async {
      await keys.write('k');
      await seed(baseUrl: 'https://example.test/v1', modelId: 'vision-model');

      await tester.pumpWidget(app());
      await settle(tester);

      expect(find.textContaining('Model: vision-model'), findsOneWidget);
    });
  });

  group('verification gates persistence', () {
    testWidgets('an empty key is refused before any request', (tester) async {
      await tester.pumpWidget(app());
      await settle(tester);

      await tester.tap(find.text('Verify and list models'));
      await settle(tester);

      expect(find.text('Enter an API key.'), findsOneWidget);
      expect(await keys.read(), isNull, reason: 'nothing may be stored');
    });

    testWidgets('an empty base URL is refused before any request', (
      tester,
    ) async {
      await keys.write('k');
      await tester.pumpWidget(app());
      await settle(tester);

      await tester.enterText(find.byType(TextField).first, '   ');
      await tester.tap(find.text('Verify and list models'));
      await settle(tester);

      expect(find.text('Enter a base URL.'), findsOneWidget);
    });

    testWidgets('a failed check stores nothing and clears the model list', (
      tester,
    ) async {
      // The endpoint is unreachable from a test, so this exercises the real
      // failure path: the key must not be persisted on a failed verification.
      await tester.pumpWidget(app());
      await settle(tester);

      await tester.enterText(
        find.byType(TextField).first,
        'https://127.0.0.1:9/v1',
      );
      await tester.enterText(find.byType(TextField).last, 'unverified-key');
      await tester.tap(find.text('Verify and list models'));
      await settle(tester);

      expect(
        await keys.read(),
        isNull,
        reason: 'a key that has never authenticated is not a configuration',
      );
      expect(find.text('Choose a model'), findsNothing);
    });
  });

  group('defaults and removal', () {
    testWidgets('prefills the documented default base URL', (tester) async {
      await tester.pumpWidget(app());
      await settle(tester);

      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(
        field.controller?.text,
        'https://api.synthetic.new/openai/v1',
        reason: 'the /openai/v1 path is the one that resolves',
      );
    });

    testWidgets('removal deletes the stored key', (tester) async {
      await keys.write('to-be-deleted');
      await seed(baseUrl: 'https://example.test/v1', modelId: 'm');

      await tester.pumpWidget(app());
      await settle(tester);

      await tester.tap(find.text('Remove configuration'));
      await settle(tester);
      await tester.tap(find.text('Remove'));
      await settle(tester);

      expect(
        await keys.read(),
        isNull,
        reason:
            'leaving the key behind would keep a credential the learner '
            'believes they deleted',
      );
      expect(find.text('A key is stored'), findsNothing);
    });

    testWidgets('removal can be cancelled', (tester) async {
      await keys.write('keep-me');
      await seed(baseUrl: 'https://example.test/v1', modelId: 'm');

      await tester.pumpWidget(app());
      await settle(tester);

      await tester.tap(find.text('Remove configuration'));
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(await keys.read(), 'keep-me');
    });
  });
}
