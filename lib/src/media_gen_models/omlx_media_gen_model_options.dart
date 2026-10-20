import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:meta/meta.dart';

/// Options for oMLX media generation (Text-to-Speech via `/v1/audio/speech`).
@immutable
class OmlxMediaGenerationModelOptions extends MediaGenerationModelOptions {
  /// Creates a new [OmlxMediaGenerationModelOptions] instance.
  const OmlxMediaGenerationModelOptions({
    this.voice = 'af_heart',
    this.responseFormat = 'mp3',
    this.speed = 1.0,
  });

  /// Voice to use for synthesis (e.g. `'af_heart'`, `'alloy'`, `'am_adam'`).
  final String? voice;

  /// Audio response format: `'mp3'`, `'opus'`, `'aac'`, `'flac'`, `'wav'`, or `'pcm'`.
  final String? responseFormat;

  /// Speech speed multiplier between 0.25 and 4.0 (default: 1.0).
  final double? speed;

  /// Returns a copy with non-null fields from [other] overriding this instance.
  OmlxMediaGenerationModelOptions mergeWith(
    OmlxMediaGenerationModelOptions? other,
  ) {
    if (other == null) return this;
    return OmlxMediaGenerationModelOptions(
      voice: other.voice ?? voice,
      responseFormat: other.responseFormat ?? responseFormat,
      speed: other.speed ?? speed,
    );
  }
}
