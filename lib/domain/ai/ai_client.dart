/// A model offered by an OpenAI-compatible endpoint.
class AiModel {
  const new({
    required this.id,
    this.displayName,
    this.supportsVision,
    this.supportsStructuredOutput = false,
  });

  final String id;
  final String? displayName;

  /// Whether the endpoint declares image input.
  ///
  /// **Null means unknown**, which is the common case: a plain
  /// OpenAI-compatible `/models` response carries only `id`. Unknown is treated
  /// as "present but unverified", never as "unsupported", so a third-party
  /// endpoint does not silently lose its vision models.
  final bool? supportsVision;

  final bool supportsStructuredOutput;

  String get label => displayName ?? id;

  @override
  String toString() => 'AiModel($id, vision=$supportsVision)';
}

/// Result of checking a base URL and key.
class CredentialCheck {
  const new({required this.ok, this.message, this.models = const <AiModel>[]});

  final bool ok;

  /// Human-readable reason when [ok] is false.
  final String? message;

  final List<AiModel> models;
}

/// The AI features the app depends on.
///
/// An interface so the import flow can be tested without a network. The
/// implementation is deliberately not in `domain/`: this layer must stay free
/// of HTTP and Flutter.
abstract interface class AiClient {
  /// Verifies the credentials **and** returns the available models.
  ///
  /// Implementations must send an authenticated request. Listing models is not
  /// sufficient on every endpoint, because some serve `/models` publicly and
  /// will happily return a full list for an invalid key.
  Future<CredentialCheck> verify();

  Future<List<AiModel>> listModels();

  /// Sends [imageBase64] (raw, no data-URL prefix) and returns the raw response
  /// body for parsing.
  ///
  /// Returns the body rather than parsed cards so the parsing rules stay in the
  /// domain layer, where they are testable without a client.
  Future<String> generateCardsFromImage({
    required String modelId,
    required String imageBase64,
    required String mimeType,
    required String systemPrompt,
    required String instruction,
  });
}

/// Thrown when a request fails in a way the caller should report.
class AiException implements Exception {
  const new(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'AiException($statusCode): $message';
}
