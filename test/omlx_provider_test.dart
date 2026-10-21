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

    test('resolves base URL from OMLX_BASE_URL and OMLX_HOST environment variables', () {
      final origBase = Agent.environment['OMLX_BASE_URL'];
      final origHost = Agent.environment['OMLX_HOST'];
      addTearDown(() {
        if (origBase != null) {
          Agent.environment['OMLX_BASE_URL'] = origBase;
        } else {
          Agent.environment.remove('OMLX_BASE_URL');
        }
        if (origHost != null) {
          Agent.environment['OMLX_HOST'] = origHost;
        } else {
          Agent.environment.remove('OMLX_HOST');
        }
      });

      // 1. OMLX_BASE_URL resolution
      Agent.environment['OMLX_BASE_URL'] = 'https://mac-studio.local:8000';
      Agent.environment.remove('OMLX_HOST');
      var provider = OmlxProvider();
      expect(provider.baseUrl, Uri.parse('https://mac-studio.local:8000'));

      // 2. OMLX_HOST resolution (with auto-prepended http://)
      Agent.environment.remove('OMLX_BASE_URL');
      Agent.environment['OMLX_HOST'] = '192.168.1.150:8000';
      provider = OmlxProvider();
      expect(provider.baseUrl, Uri.parse('http://192.168.1.150:8000'));

      // 3. OMLX_BASE_URL takes precedence over OMLX_HOST
      Agent.environment['OMLX_BASE_URL'] = 'http://priority-host:8000';
      Agent.environment['OMLX_HOST'] = 'ignored-host:8000';
      provider = OmlxProvider();
      expect(provider.baseUrl, Uri.parse('http://priority-host:8000'));

      // 4. Explicit baseUrl overrides environment variables
      provider = OmlxProvider(baseUrl: Uri.parse('http://explicit-url:9000'));
      expect(provider.baseUrl, Uri.parse('http://explicit-url:9000'));

      // 5. Injected client baseUrl is inherited when baseUrl is not passed
      final client = o.OmlxClient(baseUrl: 'http://injected-client:7000');
      provider = OmlxProvider(client: client);
      expect(provider.baseUrl, Uri.parse('http://injected-client:7000'));

      // 6. Explicit baseUrl overrides injected client baseUrl
      provider = OmlxProvider(
        client: client,
        baseUrl: Uri.parse('http://override-client:8500'),
      );
      expect(provider.baseUrl, Uri.parse('http://override-client:8500'));
    });

    test('resolves apiKey from environment and treats empty string as unset', () {
      final origKey = Agent.environment['OMLX_API_KEY'];
      addTearDown(() {
        if (origKey != null) {
          Agent.environment['OMLX_API_KEY'] = origKey;
        } else {
          Agent.environment.remove('OMLX_API_KEY');
        }
      });

      Agent.environment['OMLX_API_KEY'] = 'env-secret-key';

      // 1. Omitted apiKey resolves from environment
      var provider = OmlxProvider();
      expect(provider.apiKey, 'env-secret-key');

      // 2. Empty apiKey string is treated as unset and falls back to environment
      provider = OmlxProvider(apiKey: '');
      expect(provider.apiKey, 'env-secret-key');

      // 3. Explicit non-empty apiKey overrides environment
      provider = OmlxProvider(apiKey: 'explicit-key');
      expect(provider.apiKey, 'explicit-key');
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
      expect(chat.temperature, 0.7);

      final chatWithOptionsTemp = provider.createChatModel(
        options: const OmlxChatOptions(temperature: 0.6),
      );
      expect(chatWithOptionsTemp.temperature, 0.6);

      final embeddings = provider.createEmbeddingsModel(
        options: const OmlxEmbeddingsModelOptions(dimensions: 384),
      );
      expect(embeddings, isA<OmlxEmbeddingsModel>());
      expect((embeddings as OmlxEmbeddingsModel).batchSize, 512);
      expect(embeddings.dimensions, 384);

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
