import 'dart:convert';
import 'dart:typed_data';

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

    test('embedDocuments decodes base64-encoded float32 embeddings', () async {
      // Encode [1.0, 2.0] into little-endian float32 bytes, then base64
      final byteData = ByteData(8);
      byteData.setFloat32(0, 1.0, Endian.little);
      byteData.setFloat32(4, 2.0, Endian.little);
      final b64 = base64Encode(byteData.buffer.asUint8List());

      final mock = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['encoding_format'], 'base64');

        return http.Response(
          jsonEncode({
            'object': 'list',
            'model': 'bge-micro',
            'data': [
              {
                'object': 'embedding',
                'index': 0,
                'embedding': b64,
              }
            ],
            'usage': {'prompt_tokens': 2, 'total_tokens': 2},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final model = OmlxEmbeddingsModel(
        name: 'bge-micro',
        httpClient: mock,
      );

      final result = await model.embedDocuments(
        ['Base64 test'],
        options: const OmlxEmbeddingsModelOptions(encodingFormat: 'base64'),
      );

      expect(result.output.length, 1);
      final vector = result.output.first;
      expect(vector.length, 2);
      expect((vector[0] - 1.0).abs() < 1e-6, isTrue);
      expect((vector[1] - 2.0).abs() < 1e-6, isTrue);
    });

    test('embedDocuments returns empty for empty input', () async {
      final model = OmlxEmbeddingsModel(name: 'bge-micro');
      final result = await model.embedDocuments([]);
      expect(result.output, isEmpty);
      expect(result.count, 0);
    });
  });
}
