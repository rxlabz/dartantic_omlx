import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:domlx/domlx.dart' as o;
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../shared/omlx_utils.dart';
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
             baseUrl: OmlxUtils.resolveBaseUrl(baseUrl).toString(),
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
  static final defaultBaseUrl = OmlxUtils.defaultBaseUrl;

  /// Supported audio formats for oMLX TTS.
  static const supportedFormats = {'mp3', 'wav', 'opus', 'aac', 'flac', 'pcm'};

  /// Supported audio MIME types for oMLX TTS.
  static const supportedMimeTypes = {
    'audio/mp3': 'mp3',
    'audio/mpeg': 'mp3',
    'audio/wav': 'wav',
    'audio/x-wav': 'wav',
    'audio/opus': 'opus',
    'audio/aac': 'aac',
    'audio/flac': 'flac',
    'audio/pcm': 'pcm',
  };

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

    final hasAudioRequest = mimeTypes.any((m) {
      final lower = m.trim().toLowerCase();
      return lower == 'audio/*' || lower.startsWith('audio/');
    });

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
    if (preferredFormat != null && preferredFormat.trim().isNotEmpty) {
      final normalized = preferredFormat.trim().toLowerCase();
      final mime = switch (normalized) {
        'mp3' => 'audio/mp3',
        'wav' => 'audio/wav',
        'opus' => 'audio/opus',
        'aac' => 'audio/aac',
        'flac' => 'audio/flac',
        'pcm' => 'audio/pcm',
        _ => throw ArgumentError.value(
            preferredFormat,
            'responseFormat',
            'Unsupported audio format "$preferredFormat". '
            'Supported formats: ${supportedFormats.join(', ')}',
          ),
      };
      return (mime, normalized);
    }

    for (final mime in mimeTypes) {
      final lower = mime.trim().toLowerCase();
      if (lower == 'audio/*' || lower == 'audio/mp3' || lower == 'audio/mpeg') {
        return ('audio/mp3', 'mp3');
      }
      if (lower == 'audio/wav' || lower == 'audio/x-wav') {
        return ('audio/wav', 'wav');
      }
      if (lower == 'audio/opus') return ('audio/opus', 'opus');
      if (lower == 'audio/aac') return ('audio/aac', 'aac');
      if (lower == 'audio/flac') return ('audio/flac', 'flac');
      if (lower == 'audio/pcm') return ('audio/pcm', 'pcm');
    }

    throw UnsupportedError(
      'None of the requested audio MIME types are supported: ${mimeTypes.join(', ')}. '
      'Supported MIME types: ${supportedMimeTypes.keys.join(', ')}, audio/*.',
    );
  }

  @override
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
