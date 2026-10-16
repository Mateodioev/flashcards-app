import 'dart:convert';

import 'package:flashcards2/domain/ai/ai_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Where the API key lives.
///
/// Deliberately narrow: the key is written here and nowhere else. It never
/// touches the database, the logs, or an export.
abstract interface class ApiKeyStore {
  Future<String?> read();

  Future<void> write(String key);

  Future<void> clear();
}

/// Keystore/Keychain-backed [ApiKeyStore].
class SecureApiKeyStore implements ApiKeyStore {
  new([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'ai_api_key';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String key) => _storage.write(key: _key, value: key);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// In-memory [ApiKeyStore] for tests.
class InMemoryApiKeyStore implements ApiKeyStore {
  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String key) async => _value = key;

  @override
  Future<void> clear() async => _value = null;
}

/// OpenAI-compatible HTTP client.
class OpenAiCompatibleClient implements AiClient {
  const new({
    required this.baseUrl,
    required this.apiKey,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 60),
  }) : _http = httpClient;

  /// Base URL including any version segment, e.g.
  /// `https://api.synthetic.new/openai/v1`.
  final String baseUrl;

  final String apiKey;
  final Duration timeout;
  final http.Client? _http;

  http.Client get _client => _http ?? http.Client();

  Map<String, String> get _headers => <String, String>{
    'authorization': 'Bearer $apiKey',
    'content-type': 'application/json',
  };

  Uri _uri(String path) {
    final trimmed = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$trimmed/$path');
  }

  /// Verifies the key against an **authenticated** endpoint.
  ///
  /// This deliberately does not use `GET /models`. Verified against the live
  /// provider: `/models` is served **publicly** and returns `200` with a full
  /// model list even for a deliberately invalid key, so a check built on it
  /// would report success for any garbage input. The probe here is a minimal
  /// `chat/completions` call, which does reject a bad key — that is what makes
  /// this check meaningful.
  @override
  Future<CredentialCheck> verify() async {
    try {
      final response = await _client
          .post(
            _uri('chat/completions'),
            headers: _headers,
            body: jsonEncode(<String, Object?>{
              'model': 'probe',
              'messages': <Object?>[
                <String, Object?>{'role': 'user', 'content': 'ping'},
              ],
              'max_tokens': 1,
            }),
          )
          .timeout(timeout);

      // 401/403 mean the key is wrong. Anything else — including 404 for the
      // bogus probe model — means the key passed authentication, because the
      // endpoint checks credentials before it resolves the model.
      if (response.statusCode == 401 || response.statusCode == 403) {
        return CredentialCheck(
          ok: false,
          message: _errorMessage(response) ?? 'The API key was rejected.',
        );
      }

      final models = await listModels();
      return CredentialCheck(ok: true, models: models);
    } on Exception catch (e) {
      return CredentialCheck(ok: false, message: _describe(e));
    }
  }

  @override
  Future<List<AiModel>> listModels() async {
    try {
      final response = await _client
          .get(_uri('models'), headers: _headers)
          .timeout(timeout);
      if (response.statusCode != 200) {
        throw AiException(
          _errorMessage(response) ?? 'Could not list models.',
          statusCode: response.statusCode,
        );
      }
      return _parseModels(response.body);
    } on AiException {
      rethrow;
    } on Exception catch (e) {
      throw AiException(_describe(e));
    }
  }

  @override
  Future<String> generateCardsFromImage({
    required String modelId,
    required String imageBase64,
    required String mimeType,
    required String systemPrompt,
    required String instruction,
  }) async {
    try {
      final response = await _client
          .post(
            _uri('chat/completions'),
            headers: _headers,
            body: jsonEncode(<String, Object?>{
              'model': modelId,
              'messages': <Object?>[
                <String, Object?>{'role': 'system', 'content': systemPrompt},
                <String, Object?>{
                  'role': 'user',
                  'content': <Object?>[
                    <String, Object?>{'type': 'text', 'text': instruction},
                    <String, Object?>{
                      'type': 'image_url',
                      'image_url': <String, Object?>{
                        // The data-URL prefix is required by the OpenAI shape;
                        // the caller passes raw base64.
                        'url': 'data:$mimeType;base64,$imageBase64',
                      },
                    },
                  ],
                },
              ],
            }),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        throw AiException(
          _errorMessage(response) ?? 'The model request failed.',
          statusCode: response.statusCode,
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?>) {
        throw const AiException('The response was not a JSON object.');
      }
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) {
        throw const AiException('The response contained no choices.');
      }
      final first = choices.first;
      if (first is! Map) {
        throw const AiException('The response choice was malformed.');
      }
      final message = first['message'];
      if (message is! Map) {
        throw const AiException('The response choice had no message.');
      }
      final content = message['content'];
      if (content is! String) {
        throw const AiException('The response message had no text content.');
      }
      return content;
    } on AiException {
      rethrow;
    } on FormatException {
      throw const AiException('The response was not valid JSON.');
    } on Exception catch (e) {
      throw AiException(_describe(e));
    }
  }

  /// Reads whatever the endpoint offers about each model, tolerating absence.
  ///
  /// A plain OpenAI-compatible `/models` returns only `id`; the richer fields
  /// below are extensions. Missing `input_modalities` yields `null`
  /// ("unknown"), never `false`, so a third-party endpoint does not appear to
  /// have no vision models when it simply does not say.
  static List<AiModel> _parseModels(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map || decoded['data'] is! List) {
      throw const AiException('The model list was not in the expected shape.');
    }

    final models = <AiModel>[];
    for (final entry in decoded['data'] as List) {
      if (entry is! Map) continue;
      final id = entry['id'];
      if (id is! String || id.isEmpty) continue;

      final object = entry.cast<String, Object?>();
      models.add(
        AiModel(
          id: id,
          displayName: object['display_name'] as String?,
          supportsVision: _readVision(object),
          supportsStructuredOutput: _readFeature(object, 'structured_outputs'),
        ),
      );
    }
    return models;
  }

  static bool? _readVision(Map<String, Object?> object) {
    final modalities = object['input_modalities'];
    if (modalities is! List) return null;
    return modalities.contains('image');
  }

  static bool _readFeature(Map<String, Object?> object, String feature) {
    final features = object['supported_features'];
    if (features is! List) return false;
    return features.contains(feature);
  }

  /// Pulls the provider's error text, which is more useful than a status code.
  static String? _errorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] != null) {
        final error = decoded['error'];
        if (error is String) return error;
        if (error is Map && error['message'] is String) {
          return error['message'] as String;
        }
      }
    } on FormatException {
      // Fall through to the generic message.
    }
    return null;
  }

  static String _describe(Exception e) {
    final text = e.toString();
    if (text.contains('TimeoutException')) {
      return 'The request timed out. Check the base URL and your connection.';
    }
    if (text.contains('SocketException') || text.contains('ClientException')) {
      return 'Could not reach the endpoint. Check the base URL and your '
          'connection.';
    }
    return 'The request failed: $text';
  }
}
