import 'dart:convert';

import 'package:flashcards2/data/ai/openai_compatible_client.dart';
import 'package:flashcards2/domain/ai/ai_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Builds a client whose HTTP layer is a stub.
OpenAiCompatibleClient client(
  Future<http.Response> Function(http.Request request) handler, {
  String key = 'test-key',
}) {
  return OpenAiCompatibleClient(
    baseUrl: 'https://example.test/v1',
    apiKey: key,
    httpClient: MockClient(handler),
  );
}

void main() {
  group('verify — the key check must be meaningful', () {
    test('rejects a 401 with the provider message', () async {
      final c = client(
        (request) async =>
            http.Response(jsonEncode({'error': 'Invalid API Key.'}), 401),
      );
      final result = await c.verify();
      expect(result.ok, isFalse);
      expect(result.message, contains('Invalid API Key'));
    });

    test('rejects a 403', () async {
      final c = client(
        (request) async => http.Response('{"error":"Forbidden"}', 403),
      );
      expect((await c.verify()).ok, isFalse);
    });

    test('a non-auth error still means the key was accepted', () async {
      // The endpoint resolves credentials before the model, so a 404 for a
      // bogus probe model proves the key passed. Treating every non-200 as
      // auth failure would reject valid keys.
      final c = client((request) async {
        if (request.url.path.endsWith('/chat/completions')) {
          return http.Response('{"error":"model not found"}', 404);
        }
        return http.Response('{"data":[]}', 200);
      });
      expect((await c.verify()).ok, isTrue);
    });

    test('probes an authenticated endpoint, not /models', () async {
      // Verified against the live provider: /models is served publicly and
      // returns 200 for an invalid key. A check built on it would pass for any
      // garbage input, so the probe must hit chat/completions.
      final paths = <String>[];
      final c = client((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/chat/completions')) {
          return http.Response('{"error":"Invalid API Key."}', 401);
        }
        return http.Response('{"data":[]}', 200);
      });

      await c.verify();

      expect(
        paths,
        contains('/v1/chat/completions'),
        reason: 'the probe must authenticate',
      );
      expect(
        paths.first,
        endsWith('/chat/completions'),
        reason: 'the probe must come first, before listing models',
      );
    });

    test('sends the key as a Bearer authorization header', () async {
      String? authorization;
      final c = client((request) async {
        authorization = request.headers['authorization'];
        return http.Response('{"error":"Invalid API Key."}', 401);
      }, key: 'secret-123');

      await c.verify();

      expect(authorization, 'Bearer secret-123');
    });

    test('does not list models when the key is rejected', () async {
      var modelCalls = 0;
      final c = client((request) async {
        if (request.url.path.endsWith('/models')) {
          modelCalls++;
          return http.Response('{"data":[]}', 200);
        }
        return http.Response('{"error":"Invalid API Key."}', 401);
      });

      await c.verify();

      expect(modelCalls, 0);
    });

    test('reports a network failure without throwing', () async {
      final c = client(
        (request) async => throw http.ClientException('no route to host'),
      );
      final result = await c.verify();
      expect(result.ok, isFalse);
      expect(result.message, contains('Could not reach'));
    });
  });

  group('listModels', () {
    test('reads id and display_name', () async {
      final c = client(
        (request) async => http.Response(
          jsonEncode({
            'data': [
              {'id': 'syn:large:vision', 'display_name': 'Large Vision'},
            ],
          }),
          200,
        ),
      );

      final models = await c.listModels();
      expect(models.single.id, 'syn:large:vision');
      expect(models.single.label, 'Large Vision');
    });

    test('reads vision support from input_modalities', () async {
      final c = client(
        (request) async => http.Response(
          jsonEncode({
            'data': [
              {
                'id': 'vision-model',
                'input_modalities': ['text', 'image'],
              },
              {
                'id': 'text-model',
                'input_modalities': ['text'],
              },
            ],
          }),
          200,
        ),
      );

      final models = await c.listModels();
      expect(models.first.supportsVision, isTrue);
      expect(models.last.supportsVision, isFalse);
    });

    test(
      'an endpoint that does not declare modalities yields unknown, not false',
      () async {
        // A plain OpenAI-compatible /models returns only id. Reporting
        // "no vision" there would wrongly disable image import for a
        // third-party endpoint that simply does not say.
        final c = client(
          (request) async => http.Response(
            jsonEncode({
              'data': [
                {'id': 'mystery-model'},
              ],
            }),
            200,
          ),
        );

        final models = await c.listModels();
        expect(
          models.single.supportsVision,
          isNull,
          reason: 'absent means unknown, never unsupported',
        );
      },
    );

    test('skips entries with no usable id', () async {
      final c = client(
        (request) async => http.Response(
          jsonEncode({
            'data': [
              {'display_name': 'No id'},
              {'id': ''},
              {'id': 'good'},
            ],
          }),
          200,
        ),
      );

      final models = await c.listModels();
      expect(models, hasLength(1));
      expect(models.single.id, 'good');
    });

    test('throws AiException on a malformed body', () {
      final c = client((_) async => http.Response('not json', 200));
      final future = c.listModels();
      expect(future, throwsA(isA<AiException>()));
    });

    test('throws AiException on a non-200', () {
      final c = client((_) async => http.Response('{"error":"boom"}', 500));
      final future = c.listModels();
      expect(future, throwsA(isA<AiException>()));
    });
  });

  group('generateCardsFromImage', () {
    test('sends the image as a data URL with the right mime type', () async {
      Map<String, Object?>? body;
      final c = client((request) async {
        body = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '{"cards":[]}'},
              },
            ],
          }),
          200,
        );
      });

      await c.generateCardsFromImage(
        modelId: 'vision-model',
        imageBase64: 'AAAA',
        mimeType: 'image/png',
        systemPrompt: 'sys',
        instruction: 'do it',
      );

      final messages = body!['messages']! as List;
      final user = messages[1] as Map<String, Object?>;
      final content = user['content']! as List;
      final imagePart = content[1] as Map<String, Object?>;
      final imageUrl = imagePart['image_url']! as Map<String, Object?>;
      expect(imageUrl['url'], 'data:image/png;base64,AAAA');
    });

    test('returns the message content for the domain parser', () async {
      final c = client(
        (request) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '{"cards":[{"front":"Q","back":"A"}]}'},
              },
            ],
          }),
          200,
        ),
      );

      final content = await c.generateCardsFromImage(
        modelId: 'm',
        imageBase64: 'AAAA',
        mimeType: 'image/png',
        systemPrompt: 's',
        instruction: 'i',
      );
      expect(content, contains('"front":"Q"'));
    });

    test('reports a 401 without leaking the key', () async {
      final c = client(
        (request) async => http.Response('{"error":"Invalid API Key."}', 401),
        key: 'super-secret',
      );

      try {
        await c.generateCardsFromImage(
          modelId: 'm',
          imageBase64: 'AAAA',
          mimeType: 'image/png',
          systemPrompt: 's',
          instruction: 'i',
        );
        fail('expected an AiException');
      } on AiException catch (e) {
        expect(
          e.message,
          isNot(contains('super-secret')),
          reason: 'the error path must never echo the credential',
        );
      }
    });

    test('no failure path echoes the image payload', () async {
      // The payload is a photo of the learner's study material. It is the
      // largest and most private thing this app sends, so no error message may
      // contain it. A stray debugPrint of the request body would surface here
      // if it reached the message, which is the part the UI displays.
      const payload = 'QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVo';

      final handlers = <Future<http.Response> Function(http.Request)>[
        (_) async => throw http.ClientException('no route to host'),
        (_) async => http.Response('{"error":"boom"}', 500),
        (_) async => http.Response('not json at all', 200),
        (_) async => http.Response('{"choices":[]}', 200),
      ];

      for (final handler in handlers) {
        final c = client(handler);
        try {
          await c.generateCardsFromImage(
            modelId: 'm',
            imageBase64: payload,
            mimeType: 'image/png',
            systemPrompt: 's',
            instruction: 'i',
          );
          fail('every handler above should have failed');
        } on AiException catch (e) {
          expect(
            e.message,
            isNot(contains(payload)),
            reason: 'a failure message must not carry the image data',
          );
        }
      }
    });

    test('reports a response with no choices', () async {
      final c = client((request) async => http.Response('{"choices":[]}', 200));
      expect(
        () => c.generateCardsFromImage(
          modelId: 'm',
          imageBase64: 'A',
          mimeType: 'image/png',
          systemPrompt: 's',
          instruction: 'i',
        ),
        throwsA(isA<AiException>()),
      );
    });

    test('reports a message with no text content', () async {
      final c = client(
        (request) async => http.Response(
          jsonEncode({
            'choices': [
              {'message': <String, Object?>{}},
            ],
          }),
          200,
        ),
      );
      expect(
        () => c.generateCardsFromImage(
          modelId: 'm',
          imageBase64: 'A',
          mimeType: 'image/png',
          systemPrompt: 's',
          instruction: 'i',
        ),
        throwsA(isA<AiException>()),
      );
    });
  });

  group('base URL handling', () {
    test('a trailing slash does not produce a double slash', () async {
      String? path;
      final c = OpenAiCompatibleClient(
        baseUrl: 'https://example.test/v1/',
        apiKey: 'k',
        httpClient: MockClient((request) async {
          path = request.url.path;
          return http.Response('{"error":"x"}', 401);
        }),
      );

      await c.verify();
      expect(path, '/v1/chat/completions');
      expect(path, isNot(contains('//')));
    });
  });

  group('InMemoryApiKeyStore', () {
    test('round-trips and clears', () async {
      final store = InMemoryApiKeyStore();
      expect(await store.read(), isNull);
      await store.write('abc');
      expect(await store.read(), 'abc');
      await store.clear();
      expect(await store.read(), isNull);
    });
  });
}
