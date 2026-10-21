import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:domlx/domlx.dart' as o;
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'omlx_media_gen_model_options.dart';

/// Media generation model for oMLX using the Text-to-Speech (TTS) endpoint
/// (`/v1/audio/speech`).
class OmlxMediaGenerationModel
    extends MediaGenerationModel<OmlxMediaGenerationModelOptions> {
  /// Creates an [OmlxMediaGenerationModel].
  OmlxMediaGenerationModel({
    required super.name,
    OmlxMediaGenerationModelOptions? defaultOptions,
    super.tools,
    Uri? baseUrl,
    String? apiKey,
    Map<String, String>? headers,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 120),
    o.OmlxClient? client,
  }) : _client =
           client ??
           o.OmlxClient(
             baseUrl: (baseUrl ?? defaultBaseUrl).toString(),
             apiKey: apiKey,
             client: httpClient,
             timeout: timeout,
             defaultHeaders: headers ?? const {},
           ),
       _ownsClient = client == null,
       super(
         defaultOptions:
             defaultOptions ?? const OmlxMediaGenerationModelOptions(),
       ) {
    _logger.info('Created oMLX media generation model: $name');
  }

  /// Default base URL for oMLX.
  static final defaultBaseUrl = Uri.parse('http://localhost:8000');

  static final Logger _logger = Logger('dartantic.media.models.omlx');

  final o.OmlxClient _client;
  final bool _ownsClient;

  @override
  Stream<MediaGenerationResult> generateMediaStream(
    String prompt, {
    required List<String> mimeTypes,
    List<ChatMessage> history = const [],
    List<Part> attachments = const [],
    OmlxMediaGenerationModelOptions? options,
    Schema? outputSchema,
  }) async* {
    if (outputSchema != null) {
      throw UnsupportedError(
        'oMLX media generation does not support output schemas.',
      );
    }

    if (prompt.trim().isEmpty) {
      throw ArgumentError.value(
        prompt,
        'prompt',
        'TTS input prompt cannot be empty.',
      );
    }

    final hasAudioRequest = mimeTypes.any(
      (m) => m == 'audio/*' || m.startsWith('audio/'),
    );

    if (!hasAudioRequest) {
      throw UnsupportedError(
        'oMLX media generation only supports audio TTS (e.g. "audio/mp3", "audio/wav"). '
        'Requested MIME types: ${mimeTypes.join(', ')}',
      );
    }

    final mergedOptions = defaultOptions.mergeWith(options);
    final (resolvedMimeType, formatExtension) = _resolveAudioFormat(
      mimeTypes,
      mergedOptions.responseFormat,
    );

    final voice = mergedOptions.voice ?? 'af_heart';
    final speed = mergedOptions.speed ?? 1.0;

    _logger.info(
      'Generating speech with oMLX model "$name" '
      '(voice: $voice, format: $formatExtension)',
    );

    final request = o.AudioSpeechRequest(
      model: name,
      input: prompt,
      voice: voice,
      responseFormat: formatExtension,
      speed: speed,
    );

    final bytes = await _client.audio.speech(request);

    final asset = DataPart(
      bytes,
      mimeType: resolvedMimeType,
      name: 'speech.$formatExtension',
    );

    yield MediaGenerationResult(
      assets: [asset],
      messages: const [],
      finishReason: FinishReason.stop,
      isComplete: true,
      metadata: {
        'model': name,
        'voice': voice,
        'format': formatExtension,
        'mime_type': resolvedMimeType,
        'byte_length': bytes.length,
      },
    );
  }

  (String mimeType, String format) _resolveAudioFormat(
    List<String> mimeTypes,
    String? preferredFormat,
  ) {
    if (preferredFormat != null && preferredFormat.isNotEmpty) {
      final mime = switch (preferredFormat.toLowerCase()) {
        'wav' => 'audio/wav',
        'opus' => 'audio/opus',
        'aac' => 'audio/aac',
        'flac' => 'audio/flac',
        'pcm' => 'audio/pcm',
        _ => 'audio/mp3',
      };
      return (mime, preferredFormat.toLowerCase());
    }

    for (final mime in mimeTypes) {
      final lower = mime.toLowerCase();
      if (lower == 'audio/wav' || lower == 'audio/x-wav') {
        return ('audio/wav', 'wav');
      }
      if (lower == 'audio/opus') return ('audio/opus', 'opus');
      if (lower == 'audio/aac') return ('audio/aac', 'aac');
      if (lower == 'audio/flac') return ('audio/flac', 'flac');
      if (lower == 'audio/pcm') return ('audio/pcm', 'pcm');
      if (lower == 'audio/mp3' || lower == 'audio/mpeg' || lower == 'audio/*') {
        return ('audio/mp3', 'mp3');
      }
    }

    return ('audio/mp3', 'mp3');
  }

  @override
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
