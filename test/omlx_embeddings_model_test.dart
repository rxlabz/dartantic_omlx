import 'dart:convert';

import 'package:dartantic_omlx/dartantic_omlx.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('OmlxEmbeddingsModel', () {
    test('embedQuery embeds a single string', () async {
      final mock = MockClient((request) async {
        expect(request.url.path, '/v1/embeddings');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['model'], 'bge-micro');
        expect(body['input'], ['Test query']);

        return http.Response(
          jsonEncode({
            'object': 'list',
            'model': 'bge-micro',
            'data': [
              {
                'object': 'embedding',
                'index': 0,
                'embedding': [0.1, 0.2, 0.3],
              }
            ],
            'usage': {'prompt_tokens': 3, 'total_tokens': 3},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final model = OmlxEmbeddingsModel(
        name: 'bge-micro',
        httpClient: mock,
      );

      final result = await model.embedQuery('Test query');
      expect(result.output, [0.1, 0.2, 0.3]);
      expect(result.usage?.promptTokens, 3);
      expect(result.usage?.totalTokens, 3);
    });

    test('embedDocuments chunks batches and sums usage', () async {
      var callCount = 0;
      final mock = MockClient((request) async {
        callCount++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final inputs = body['input'] as List;

        return http.Response(
          jsonEncode({
            'object': 'list',
            'model': 'bge-micro',
            'data': [
              for (var i = 0; i < inputs.length; i++)
                {
                  'object': 'embedding',
                  'index': i,
                  'embedding': [0.5, 0.6],
                }
            ],
            'usage': {'prompt_tokens': inputs.length * 2, 'total_tokens': inputs.length * 2},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final model = OmlxEmbeddingsModel(
        name: 'bge-micro',
        batchSize: 2,
        httpClient: mock,
      );

      final texts = ['text 1', 'text 2', 'text 3'];
      final batchResult = await model.embedDocuments(texts);

      expect(callCount, 2);
      expect(batchResult.count, 3);
      expect(batchResult.output.length, 3);
      expect(batchResult.output[0], [0.5, 0.6]);
      expect(batchResult.usage?.totalTokens, 6);
    });

    test('embedDocuments returns empty for empty input', () async {
      final model = OmlxEmbeddingsModel(name: 'bge-micro');
      final result = await model.embedDocuments([]);
      expect(result.output, isEmpty);
      expect(result.count, 0);
    });
  });
}
