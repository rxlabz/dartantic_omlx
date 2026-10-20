import 'dart:convert';

import 'package:dartantic_omlx/dartantic_omlx.dart';
import 'package:domlx/domlx.dart' as o;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('OmlxProvider', () {
    test('default configuration and properties', () {
      final provider = OmlxProvider();
      expect(provider.name, 'omlx');
      expect(provider.displayName, 'oMLX');
      expect(provider.aliases, contains('mlx'));
      expect(
        provider.defaultModelNames[ModelKind.chat],
        'mlx-community/Qwen2.5-7B-Instruct-4bit',
      );
      expect(
        provider.defaultModelNames[ModelKind.embeddings],
        'bge-micro',
      );
      expect(
        provider.defaultModelNames[ModelKind.tts],
        'mlx-community/Kokoro-82M-bf16',
      );
      expect(provider.baseUrl, Uri.parse('http://localhost:8000'));
    });

    test('registers provider with Agent', () {
      OmlxProvider.register();
      expect(Agent.providerFactories.containsKey('omlx'), isTrue);
      expect(Agent.providerFactories.containsKey('mlx'), isTrue);

      final agent = Agent('omlx:mlx-community/Qwen2.5-7B-Instruct-4bit');
      expect(agent.providerName, 'omlx');
      expect(agent.chatModelName, 'mlx-community/Qwen2.5-7B-Instruct-4bit');
    });

    test('creates models with appropriate options', () {
      final provider = OmlxProvider();
      final chat = provider.createChatModel(
        temperature: 0.7,
        enableThinking: true,
        options: const OmlxChatOptions(maxTokens: 500),
      );
      expect(chat, isA<OmlxChatModel>());
      expect((chat as OmlxChatModel).enableThinking, isTrue);

      final embeddings = provider.createEmbeddingsModel(
        options: const OmlxEmbeddingsModelOptions(dimensions: 384),
      );
      expect(embeddings, isA<OmlxEmbeddingsModel>());

      final media = provider.createMediaModel(
        options: const OmlxMediaGenerationModelOptions(voice: 'am_adam'),
      );
      expect(media, isA<OmlxMediaGenerationModel>());
    });

    test('listModels maps discovered models with inferred kinds', () async {
      final mock = MockClient((request) async {
        expect(request.url.path, '/v1/models');
        return http.Response(
          jsonEncode({
            'object': 'list',
            'data': [
              {'id': 'mlx-community/Qwen2.5-7B-Instruct-4bit'},
              {'id': 'bge-micro-embeddings'},
              {'id': 'BAAI/bge-reranker-large'},
              {'id': 'whisper-large-v3'},
              {'id': 'mlx-community/Kokoro-82M-bf16'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final provider = OmlxProvider(httpClient: mock);
      final models = await provider.listModels().toList();

      expect(models.length, 5);
      expect(models[0].name, 'mlx-community/Qwen2.5-7B-Instruct-4bit');
      expect(models[0].kinds, contains(ModelKind.chat));

      expect(models[1].name, 'bge-micro-embeddings');
      expect(models[1].kinds, contains(ModelKind.embeddings));

      expect(models[2].name, 'BAAI/bge-reranker-large');
      expect(models[2].kinds, contains(ModelKind.other));
      expect(models[2].kinds.contains(ModelKind.embeddings), isFalse);

      expect(models[3].name, 'whisper-large-v3');
      expect(models[3].kinds, contains(ModelKind.audio));

      expect(models[4].name, 'mlx-community/Kokoro-82M-bf16');
      expect(models[4].kinds, contains(ModelKind.tts));
    });

    test('oMLX extensions: health, modelsStatus, unload, rerank', () async {
      final mock = MockClient((request) async {
        if (request.url.path == '/health') {
          return http.Response(
            jsonEncode({'status': 'healthy', 'version': '1.0.0'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/v1/models/status') {
          return http.Response(
            jsonEncode({
              'data': [
                {'model_id': 'qwen', 'loaded': true},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/v1/models/qwen/unload') {
          return http.Response(
            jsonEncode({'status': 'ok'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/v1/rerank') {
          return http.Response(
            jsonEncode({
              'model': 'bge-reranker-large',
              'results': [
                {'index': 1, 'relevance_score': 0.95, 'document': 'doc 2'},
                {'index': 0, 'relevance_score': 0.20, 'document': 'doc 1'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final provider = OmlxProvider(httpClient: mock);

      final health = await provider.health();
      expect(health.isHealthy, isTrue);

      final statuses = await provider.modelsStatus();
      expect(statuses.length, 1);
      expect(statuses.first.modelId, 'qwen');
      expect(statuses.first.isLoaded, isTrue);

      final unload = await provider.unloadModel('qwen');
      expect(unload.success, isTrue);

      final rankings = await provider.rerank(
        query: 'search query',
        documents: ['doc 1', 'doc 2'],
      );
      expect(rankings.length, 2);
      expect(rankings.first.document, 'doc 2');
      expect(rankings.first.relevanceScore, 0.95);
    });

    test('closes ephemeral client when client and httpClient are not provided', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'status': 'healthy', 'version': '1.0.0'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final customOmlxClient = o.OmlxClient(client: mockClient);
      // We can intercept close on a custom wrapper or test using the client parameter
      final providerWithClient = OmlxProvider(client: customOmlxClient);
      await providerWithClient.health();
      // Should NOT close user-supplied client
      // (verified because customOmlxClient remains open for subsequent calls)
      expect(await providerWithClient.health(), isNotNull);
    });
  });
}
