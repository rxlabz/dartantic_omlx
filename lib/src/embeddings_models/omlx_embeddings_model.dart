import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:domlx/domlx.dart' as o;
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../shared/omlx_utils.dart';
import 'omlx_embeddings_model_options.dart';

/// Embeddings model backed by oMLX's `/v1/embeddings` endpoint.
class OmlxEmbeddingsModel extends EmbeddingsModel<OmlxEmbeddingsModelOptions> {
  /// Creates an [OmlxEmbeddingsModel].
  OmlxEmbeddingsModel({
    required super.name,
    super.dimensions,
    super.batchSize = 512,
    OmlxEmbeddingsModelOptions? options,
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
             options ??
             OmlxEmbeddingsModelOptions(
               dimensions: dimensions,
               batchSize: batchSize,
             ),
       ) {
    _logger.info(
      'Created oMLX embeddings model: $name '
      '(dimensions: $dimensions, batchSize: $batchSize)',
    );
  }

  /// Default base URL for oMLX server.
  static final defaultBaseUrl = Uri.parse('http://localhost:8000');

  static final Logger _logger = Logger('dartantic.embeddings.models.omlx');

  final o.OmlxClient _client;
  final bool _ownsClient;

  @override
  Future<EmbeddingsResult> embedQuery(
    String query, {
    OmlxEmbeddingsModelOptions? options,
  }) async {
    _logger.fine(
      'Embedding query with oMLX model "$name" (length: ${query.length})',
    );

    final batchResult = await embedDocuments([query], options: options);

    final embedding = batchResult.output.isNotEmpty
        ? batchResult.output.first
        : const <double>[];

    return EmbeddingsResult(
      id: batchResult.id,
      output: embedding,
      finishReason: batchResult.finishReason,
      usage: batchResult.usage,
      metadata: {
        ...batchResult.metadata,
        'query_length': query.length,
      },
    );
  }

  @override
  Future<BatchEmbeddingsResult> embedDocuments(
    List<String> texts, {
    OmlxEmbeddingsModelOptions? options,
  }) async {
    final mergedOptions = defaultOptions.mergeWith(options);
    final effectiveDimensions = mergedOptions.dimensions ?? dimensions;
    final effectiveBatchSize = mergedOptions.batchSize ?? batchSize ?? 512;

    if (texts.isEmpty) {
      return BatchEmbeddingsResult(
        output: const [],
        finishReason: FinishReason.stop,
        metadata: {
          'model': name,
          'dimensions': effectiveDimensions,
          'batch_count': 0,
          'total_texts': 0,
        },
        usage: const LanguageModelUsage(),
      );
    }

    _logger.info(
      'Embedding ${texts.length} documents with oMLX model "$name" '
      '(batchSize: $effectiveBatchSize, dimensions: $effectiveDimensions)',
    );

    final allEmbeddings = <List<double>>[];
    var totalUsage = const LanguageModelUsage();
    final batches = _chunkList(texts, effectiveBatchSize);

    for (var i = 0; i < batches.length; i++) {
      final batch = batches[i];
      _logger.fine(
        'Processing embeddings batch ${i + 1}/${batches.length} '
        '(${batch.length} texts)',
      );

      final request = o.EmbeddingRequest.batch(
        model: name,
        texts: batch,
        dimensions: effectiveDimensions,
        encodingFormat: mergedOptions.encodingFormat,
        user: mergedOptions.user,
      );

      final response = await _client.embeddings.create(request);

      for (final item in response.data) {
        final emb = item.embedding;
        if (emb != null) {
          allEmbeddings.add(emb);
        }
      }

      final usage = OmlxUtils.mapUsage(response.usage);
      if (usage != null) {
        totalUsage = totalUsage.concat(usage);
      }
    }

    return BatchEmbeddingsResult(
      output: allEmbeddings,
      finishReason: FinishReason.stop,
      metadata: {
        'model': name,
        'dimensions': effectiveDimensions,
        'batch_count': batches.length,
        'total_texts': texts.length,
      },
      usage: totalUsage,
    );
  }

  static List<List<T>> _chunkList<T>(List<T> list, int chunkSize) {
    if (chunkSize <= 0) return [list];
    final chunks = <List<T>>[];
    for (var i = 0; i < list.length; i += chunkSize) {
      final end = (i + chunkSize < list.length) ? i + chunkSize : list.length;
      chunks.add(list.sublist(i, end));
    }
    return chunks;
  }

  @override
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
