import 'dart:convert';
import 'dart:typed_data';

import 'package:dartantic_omlx/dartantic_omlx.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('OmlxMediaGenerationModel', () {
    test('synthesizes audio speech for audio mime type', () async {
      final fakeAudioBytes = Uint8List.fromList([0xFF, 0xFB, 0x90, 0x00]);

      final mock = MockClient((request) async {
        expect(request.url.path, '/v1/audio/speech');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['model'], 'kokoro');
        expect(body['input'], 'Hello world from oMLX');
        expect(body['voice'], 'af_heart');
        expect(body['response_format'], 'mp3');

        return http.Response.bytes(
          fakeAudioBytes,
          200,
          headers: {'content-type': 'audio/mpeg'},
        );
      });

      final model = OmlxMediaGenerationModel(
        name: 'kokoro',
        httpClient: mock,
      );

      final results = await model.generateMediaStream(
        'Hello world from oMLX',
        mimeTypes: ['audio/mp3'],
      ).toList();

      expect(results.length, 1);
      final result = results.first;
      expect(result.isComplete, isTrue);
      expect(result.assets.length, 1);
      final asset = result.assets.first;
      expect(asset, isA<DataPart>());
      final dataPart = asset as DataPart;
      expect(dataPart.mimeType, 'audio/mp3');
      expect(dataPart.bytes, fakeAudioBytes);
      expect(result.metadata['format'], 'mp3');
      expect(result.metadata['voice'], 'af_heart');
    });

    test('respects audio/wav requested in mimeTypes when options.responseFormat is not set', () async {
      final fakeWavBytes = Uint8List.fromList([0x52, 0x49, 0x46, 0x46]);

      final mock = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['response_format'], 'wav');

        return http.Response.bytes(
          fakeWavBytes,
          200,
          headers: {'content-type': 'audio/wav'},
        );
      });

      final model = OmlxMediaGenerationModel(
        name: 'kokoro',
        httpClient: mock,
      );

      final results = await model.generateMediaStream(
        'Speech in WAV',
        mimeTypes: ['audio/wav'],
      ).toList();

      expect(results.length, 1);
      final result = results.first;
      expect(result.metadata['format'], 'wav');
      expect(result.metadata['mime_type'], 'audio/wav');
      final asset = result.assets.first as DataPart;
      expect(asset.mimeType, 'audio/wav');
      expect(asset.name, 'speech.wav');
    });

    test('explicit options.responseFormat overrides mimeTypes', () async {
      final fakeFlacBytes = Uint8List.fromList([0x66, 0x4C, 0x61, 0x43]);

      final mock = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['response_format'], 'flac');

        return http.Response.bytes(
          fakeFlacBytes,
          200,
          headers: {'content-type': 'audio/flac'},
        );
      });

      final model = OmlxMediaGenerationModel(
        name: 'kokoro',
        httpClient: mock,
      );

      final results = await model.generateMediaStream(
        'Speech in FLAC',
        mimeTypes: ['audio/wav'],
        options: const OmlxMediaGenerationModelOptions(responseFormat: 'flac'),
      ).toList();

      expect(results.length, 1);
      final result = results.first;
      expect(result.metadata['format'], 'flac');
      expect(result.metadata['mime_type'], 'audio/flac');
    });

    test('rejects non-audio mime type requests', () {
      final model = OmlxMediaGenerationModel(name: 'kokoro');

      expect(
        () => model.generateMediaStream(
          'A cat photo',
          mimeTypes: ['image/png'],
        ).toList(),
        throwsUnsupportedError,
      );
    });

    test('rejects output schemas', () {
      final model = OmlxMediaGenerationModel(name: 'kokoro');

      expect(
        () => model.generateMediaStream(
          'Prompt',
          mimeTypes: ['audio/mp3'],
          outputSchema: S.object(),
        ).toList(),
        throwsUnsupportedError,
      );
    });
  });
}
