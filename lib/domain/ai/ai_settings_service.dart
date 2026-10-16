import 'package:flashcards2/data/ai/openai_compatible_client.dart';
import 'package:flashcards2/domain/ai/ai_client.dart';
import 'package:flashcards2/domain/entities/scheduling.dart';
import 'package:flashcards2/domain/repositories/settings_repository.dart';

/// The persisted AI configuration, if the key is present.
class AiConfiguration {
  const new({required this.baseUrl, required this.apiKey, this.modelId});

  final String baseUrl;
  final String apiKey;
  final String? modelId;

  bool get hasModel => modelId != null && modelId!.isNotEmpty;
}

/// Reads and writes the AI settings.
///
/// The base URL and model id live in the database; the **key never does**. It
/// is read from and written to secure storage only, so no backup, export, or
/// database inspection can surface it.
class AiSettingsService {
  const new(
    this._settings,
    this._keys, {
    this.defaultBaseUrl = kDefaultBaseUrl,
  });

  /// Default endpoint. The OpenAI-compatible path includes the version segment.
  static const String kDefaultBaseUrl = 'https://api.synthetic.new/openai/v1';

  final SettingsRepository _settings;
  final ApiKeyStore _keys;
  final String defaultBaseUrl;

  /// Whether the feature is usable. Image import stays disabled until this is
  /// true, per the plan: a missing key must not leave a half-working feature.
  Future<bool> isConfigured() async {
    final config = await read();
    return config != null && config.hasModel;
  }

  /// The stored configuration, or null when the key is absent.
  Future<AiConfiguration?> read() async {
    final key = await _keys.read();
    if (key == null || key.trim().isEmpty) return null;

    final row = await _settings.read();
    return AiConfiguration(
      baseUrl: row.apiBaseUrl ?? defaultBaseUrl,
      apiKey: key,
      modelId: row.apiModelId,
    );
  }

  /// Builds a client from stored settings, or null when unconfigured.
  Future<AiClient?> client() async {
    final config = await read();
    if (config == null) return null;
    return OpenAiCompatibleClient(
      baseUrl: config.baseUrl,
      apiKey: config.apiKey,
    );
  }

  /// Verifies a candidate configuration **before** anything is persisted.
  ///
  /// Persisting an unverified key would leave the feature enabled against an
  /// endpoint that does not work, which is worse than leaving it off.
  Future<CredentialCheck> testCredentials({
    required String baseUrl,
    required String apiKey,
  }) {
    final client = OpenAiCompatibleClient(
      baseUrl: baseUrl.trim(),
      apiKey: apiKey.trim(),
    );
    return client.verify();
  }

  /// Stores a verified configuration.
  ///
  /// [verifiedAt] is recorded so the UI can show when the check last passed
  /// rather than implying the key is permanently good.
  Future<void> save({
    required String baseUrl,
    required String apiKey,
    required String modelId,
    required DateTime verifiedAt,
  }) async {
    await _keys.write(apiKey.trim());
    final current = await _settings.read();
    await _settings.update(
      current.copyWith(
        apiBaseUrl: baseUrl.trim(),
        apiModelId: modelId,
        apiConfiguredAt: verifiedAt,
      ),
    );
  }

  /// Records a model change without touching the key.
  Future<void> selectModel(String modelId) async {
    final current = await _settings.read();
    await _settings.update(current.copyWith(apiModelId: modelId));
  }

  /// Removes the configuration and the key.
  ///
  /// Clearing the key is the point: leaving it in secure storage after the
  /// learner removes the configuration would keep a credential they believe
  /// they deleted.
  Future<void> clear() async {
    await _keys.clear();
    final current = await _settings.read();
    await _settings.update(
      AppSettings(
        id: AppSettings.singletonId,
        themeMode: current.themeMode,
        dayCutoffHour: current.dayCutoffHour,
        memorySpan: current.memorySpan,
        forcedGenerationBarrier: current.forcedGenerationBarrier,
        onboardingCompletedAt: current.onboardingCompletedAt,
      ),
    );
  }
}
