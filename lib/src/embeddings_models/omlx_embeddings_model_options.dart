import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:meta/meta.dart';

/// Options for oMLX embeddings models (`/v1/embeddings`).
@immutable
class OmlxEmbeddingsModelOptions extends EmbeddingsModelOptions {
  /// Creates a new [OmlxEmbeddingsModelOptions] instance.
  const OmlxEmbeddingsModelOptions({
    super.dimensions,
    super.batchSize,
    this.encodingFormat,
    this.user,
    this.extra,
  });

  /// Optional encoding format: `"float"` (default) or `"base64"`.
  final String? encodingFormat;

  /// Optional user identifier for tracking.
  final String? user;

  /// Extra custom parameters passed to the request.
  final Map<String, dynamic>? extra;

  /// Returns a copy with non-null fields from [other] overriding this instance.
  OmlxEmbeddingsModelOptions mergeWith(OmlxEmbeddingsModelOptions? other) {
    if (other == null) return this;
    return OmlxEmbeddingsModelOptions(
      dimensions: other.dimensions ?? dimensions,
      batchSize: other.batchSize ?? batchSize,
      encodingFormat: other.encodingFormat ?? encodingFormat,
      user: other.user ?? user,
      extra: {...?extra, ...?other.extra},
    );
  }
}
