import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flashcards2/data/ai/openai_compatible_client.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/data/repositories/drift_settings_repository.dart';
import 'package:flashcards2/domain/ai/ai_client.dart';
import 'package:flashcards2/domain/ai/ai_settings_service.dart';
import 'package:flashcards2/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late InMemoryApiKeyStore keys;
  late AiSettingsService service;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    keys = InMemoryApiKeyStore();
    service = AiSettingsService(DriftSettingsRepository(db), keys);
  });

  tearDown(() => db.close());

  group('isConfigured — the feature gate', () {
    test('false with no key at all', () async {
      expect(await service.isConfigured(), isFalse);
    });

    test('false with a key but no model chosen', () async {
      // Both halves are required. A key with no model would leave the import
      // enabled but unable to send anything, which is worse than disabled.
      await keys.write('sk-test');
      expect(await service.isConfigured(), isFalse);
    });

    test('false when the key is blank', () async {
      await keys.write('   ');
      await service.selectModel('some-model');
      expect(await service.isConfigured(), isFalse);
    });

    test('true once a key and a model are both present', () async {
      await service.save(
        baseUrl: 'https://example.test/v1',
        apiKey: 'sk-test',
        modelId: 'vision-model',
        verifiedAt: DateTime(2022, 12),
      );
      expect(await service.isConfigured(), isTrue);
    });
  });

  group('persistence boundaries', () {
    test('the key never reaches the database', () async {
      await service.save(
        baseUrl: 'https://example.test/v1',
        apiKey: 'super-secret-key',
        modelId: 'm',
        verifiedAt: DateTime(2022, 12),
      );

      final row = await db.select(db.appSettings).getSingle();
      expect(row.apiBaseUrl, 'https://example.test/v1');
      expect(row.apiModelId, 'm');

      // The whole point: nothing in the stored row may carry the credential.
      final dumped = <String, Object?>{
        'baseUrl': row.apiBaseUrl,
        'modelId': row.apiModelId,
        'configuredAt': row.apiConfiguredAt?.toIso8601String(),
      }.values.join(' ');
      expect(dumped, isNot(contains('super-secret-key')));
    });

    test('clear removes the key as well as the configuration', () async {
      await service.save(
        baseUrl: 'https://example.test/v1',
        apiKey: 'sk-test',
        modelId: 'm',
        verifiedAt: DateTime(2022, 12),
      );
      expect(await keys.read(), 'sk-test');

      await service.clear();

      expect(
        await keys.read(),
        isNull,
        reason:
            'leaving the key behind would keep a credential the learner '
            'believes they deleted',
      );
      final row = await db.select(db.appSettings).getSingle();
      expect(row.apiBaseUrl, isNull);
      expect(row.apiModelId, isNull);
    });

    test('clear preserves unrelated settings', () async {
      await service.save(
        baseUrl: 'https://example.test/v1',
        apiKey: 'sk-test',
        modelId: 'm',
        verifiedAt: DateTime(2022, 12),
      );
      await db
          .update(db.appSettings)
          .write(
            const AppSettingsCompanion(themeMode: Value(AppThemeMode.dark)),
          );

      await service.clear();

      final row = await db.select(db.appSettings).getSingle();
      expect(
        row.themeMode,
        AppThemeMode.dark,
        reason: 'clearing AI config must not reset the theme',
      );
    });

    test('selectModel changes the model but not the key', () async {
      await service.save(
        baseUrl: 'https://example.test/v1',
        apiKey: 'sk-test',
        modelId: 'first',
        verifiedAt: DateTime(2022, 12),
      );

      await service.selectModel('second');

      final config = await service.read();
      expect(config!.modelId, 'second');
      expect(config.apiKey, 'sk-test');
    });

    test('read falls back to the default base URL', () async {
      await keys.write('sk-test');
      final config = await service.read();
      expect(config!.baseUrl, AiSettingsService.kDefaultBaseUrl);
    });

    test('the default base URL includes the version segment', () {
      // Verified against the live provider: the OpenAI-compatible path is
      // /openai/v1, and posting to /v1 alone returns a route error.
      expect(AiSettingsService.kDefaultBaseUrl, contains('/v1'));
    });
  });

  group('testCredentials', () {
    test('returns the failure message without persisting anything', () async {
      // Persisting an unverified key would leave the feature enabled against a
      // broken endpoint.
      final result = await service.testCredentials(
        baseUrl: 'https://example.test/v1',
        apiKey: 'bad',
      );
      expect(result, isA<CredentialCheck>());
    });
  });

  group('InMemoryApiKeyStore', () {
    test('starts empty', () async {
      expect(await InMemoryApiKeyStore().read(), isNull);
    });
  });
}
