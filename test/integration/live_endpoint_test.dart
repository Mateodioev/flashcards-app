@Tags(<String>['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flashcards2/data/ai/openai_compatible_client.dart';
import 'package:flashcards2/domain/ai/flashcard_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

/// Live tests against a real OpenAI-compatible endpoint.
///
/// These are the ONLY tests that prove the network path works, and they are
/// opt-in because they need a credential and spend tokens. Everything else in
/// this project is proven against a stubbed HTTP layer, which cannot catch a
/// wrong header name, a wrong path, or a provider whose error shape differs
/// from what the code assumes.
///
/// Run with:
///   FLASHCARDS2_AI_KEY=sk-... \
///   FLASHCARDS2_AI_BASE_URL=https://api.deepseek.com/v1 \
///   FLASHCARDS2_AI_MODEL=deepseek-flash \
///   flutter test --tags integration
///
/// `flutter test` runs tagged tests by default, so CI must opt out with
/// `--exclude-tags integration` to stay offline and credential-free. Without
/// the environment variable every test here is skipped, so a missing credential
/// can never be mistaken for a pass.
void main() {
  // flutter_test installs an HttpOverrides that answers every request with a
  // synthetic 400. Live calls are impossible until it is removed.
  setUpAll(() => HttpOverrides.global = null);

  final apiKey = Platform.environment['FLASHCARDS2_AI_KEY'] ?? '';
  final baseUrl =
      Platform.environment['FLASHCARDS2_AI_BASE_URL'] ??
      'https://api.deepseek.com/v1';
  final modelId =
      Platform.environment['FLASHCARDS2_AI_MODEL'] ?? 'deepseek-flash';

  OpenAiCompatibleClient client({String? key}) => OpenAiCompatibleClient(
    baseUrl: baseUrl,
    apiKey: key ?? apiKey,
    timeout: const Duration(seconds: 120),
  );

  final skipReason = apiKey.isEmpty
      ? 'set FLASHCARDS2_AI_KEY to run live endpoint tests'
      : null;

  group('live endpoint', () {
    test('verify accepts a real key', () async {
      final result = await client().verify();

      expect(result.ok, isTrue, reason: 'verify() reported: ${result.message}');
      expect(
        result.models,
        isNotEmpty,
        reason: 'a verified endpoint should list at least one model',
      );
    }, skip: skipReason);

    test('verify rejects a bad key with the provider message', () async {
      final result = await client(key: 'sk-definitely-not-valid').verify();

      expect(result.ok, isFalse);
      expect(
        result.message,
        isNotNull,
        reason: 'the provider error text should reach the user',
      );
    }, skip: skipReason);

    test('listModels reports which models accept images', () async {
      final models = await client().listModels();

      expect(models, isNotEmpty);
      // At least one model must declare image input, or the import feature has
      // nothing to use. `null` is allowed for models that do not say, but a
      // fully-null list would mean the metadata is being dropped.
      expect(
        models.any((m) => m.supportsVision == true),
        isTrue,
        reason:
            'no model advertised image input: '
            '${models.map((m) => "${m.id}=${m.supportsVision}").join(", ")}',
      );
    }, skip: skipReason);

    test(
      'generates cards from a real image through the real parser',
      () async {
        // A plausible, clearly-structured note. A 1x1 pixel would prove
        // nothing: a model asked to read an empty image should return no
        // cards, and the assertion below would then be vacuous.
        const image = _pngBase64;

        // Guard the fixture before sending it. This literal was silently
        // corrupted once — a re-wrap dropped the final chunk, the bytes still
        // began with a valid PNG signature, and the endpoint rejected it as an
        // "unsupported image" while every unit test stayed green. Verifying
        // the digest here means the next such corruption fails on the fixture
        // rather than looking like a provider problem.
        final decoded = base64Decode(image);
        expect(
          sha256.convert(decoded).toString(),
          kStudyMaterialSha256,
          reason: 'the embedded PNG literal is corrupted or truncated',
        );
        expect(decoded.sublist(0, 8), <int>[
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
        ], reason: 'not a PNG signature');
        // A complete PNG ends with the IEND chunk. Truncation is what actually
        // happened here, and this catches it directly.
        expect(
          String.fromCharCodes(
            decoded.sublist(decoded.length - 8, decoded.length - 4),
          ),
          'IEND',
          reason: 'the PNG is truncated: no IEND trailer',
        );

        final body = await client().generateCardsFromImage(
          modelId: modelId,
          imageBase64: image,
          mimeType: 'image/png',
          systemPrompt: FlashcardPrompt.system,
          instruction: FlashcardPrompt.imageInstruction,
        );

        final parsed = FlashcardPrompt.parse(body);

        expect(
          parsed.error,
          isNull,
          reason: 'the model returned something the parser rejected: $body',
        );
        expect(
          parsed.drafts,
          isNotEmpty,
          reason: 'a page of facts should yield cards: $body',
        );
        for (final draft in parsed.drafts) {
          expect(draft.front, isNotEmpty);
          expect(draft.back, isNotEmpty);
        }
      },
      skip: skipReason,
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}

/// A small PNG holding four unambiguous facts.
///
/// Embedded as base64 rather than read from disk so the test has no fixture
/// dependency and cannot silently pass on a missing file.
///
/// [kStudyMaterialSha256] is asserted before the bytes are sent. That guard
/// exists because this literal WAS silently corrupted once: a re-wrap script
/// dropped the final chunk, the bytes still began with a valid PNG header, and
/// the endpoint rejected it as an unsupported image while every unit test
/// passed. A truncated PNG with a valid header is exactly the kind of damage
/// that has to fail loudly.
const String _pngBase64 =
    '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';

/// SHA-256 of the decoded PNG. See [_pngBase64].
const String kStudyMaterialSha256 =
    '1cdce09632a863d8c7ba9082c161b59bc64f7875cc0fbb9031aca06f70950426';
