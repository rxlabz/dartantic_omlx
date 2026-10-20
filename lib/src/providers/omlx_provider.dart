import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:domlx/domlx.dart' as o;
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../chat_models/omlx_chat.dart';
import '../embeddings_models/omlx_embeddings.dart';
import '../media_gen_models/omlx_media_gen.dart';
import '../shared/omlx_utils.dart';

/// Dartantic provider for oMLX (OpenAI-compatible inference server for Apple
/// Silicon).
class OmlxProvider
    extends
        Provider<
          OmlxChatOptions,
          OmlxEmbeddingsModelOptions,
          OmlxMediaGenerationModelOptions
        > {
  /// Creates an [OmlxProvider] instance.
  OmlxProvider({
    super.name = 'omlx',
    super.displayName = 'oMLX',
    super.defaultModelNames = const {
      ModelKind.chat: defaultChatModel,
      ModelKind.embeddings: defaultEmbeddingsModel,
      ModelKind.tts: defaultTtsModel,
      ModelKind.audio: defaultAudioModel,
      ModelKind.media: defaultTtsModel,
    },
    Uri? baseUrl,
    String? apiKey,
    super.apiKeyName = defaultApiKeyName,
    super.aliases = const ['mlx'],
    super.headers = const {},
    this.httpClient,
    this.timeout = const Duration(seconds: 300),
    this.client,
  }) : super(
         baseUrl: baseUrl ?? defaultBaseUrl,
         apiKey: apiKey ?? OmlxUtils.tryGetEnv(apiKeyName ?? defaultApiKeyName),
       );

  /// Default chat model for oMLX.
  static const defaultChatModel = 'mlx-community/Qwen2.5-7B-Instruct-4bit';

  /// Default embeddings model for oMLX.
  static const defaultEmbeddingsModel = 'bge-micro';

  /// Default TTS model for oMLX.
  static const defaultTtsModel = 'mlx-community/Kokoro-82M-bf16';

  /// Default Whisper audio model for oMLX.
  static const defaultAudioModel = 'whisper-large-v3';

  /// Default base URL for oMLX API.
  static final defaultBaseUrl = Uri.parse('http://localhost:8000');

  /// Environment variable name for oMLX API key (optional).
  static const defaultApiKeyName = 'OMLX_API_KEY';

  static final Logger _logger = Logger('dartantic.chat.providers.omlx');

  /// Optional custom HTTP client.
  final http.Client? httpClient;

  /// Request timeout.
  final Duration timeout;

  /// Optional pre-configured [o.OmlxClient].
  final o.OmlxClient? client;

  /// Registers [OmlxProvider] into [Agent.providerFactories] under `'omlx'`
  /// and `'mlx'`.
  static void register([OmlxProvider Function()? factory]) {
    final providerFactory = factory ?? OmlxProvider.new;
    Agent.providerFactories['omlx'] = providerFactory;
    Agent.providerFactories['mlx'] = providerFactory;
  }

  o.OmlxClient _getClient() {
    return client ??
        o.OmlxClient(
          baseUrl: (baseUrl ?? defaultBaseUrl).toString(),
          apiKey: apiKey,
          client: httpClient,
          timeout: timeout,
          defaultHeaders: headers,
        );
  }

  Future<T> _withClient<T>(Future<T> Function(o.OmlxClient client) action) async {
    final c = _getClient();
    final shouldClose = client == null && httpClient == null;
    try {
      return await action(c);
    } finally {
      if (shouldClose) {
        c.close();
      }
    }
  }

  @override
  ChatModel<OmlxChatOptions> createChatModel({
    String? name,
    List<Tool>? tools,
    double? temperature,
    bool enableThinking = false,
    OmlxChatOptions? options,
  }) {
    final modelName = name ?? defaultModelNames[ModelKind.chat]!;
    _logger.info(
      'Creating oMLX chat model: $modelName with ${tools?.length ?? 0} tools, '
      'temp: $temperature, thinking: $enableThinking',
    );

    return OmlxChatModel(
      name: modelName,
      tools: tools,
      temperature: temperature,
      enableThinking: enableThinking,
      baseUrl: baseUrl ?? defaultBaseUrl,
      apiKey: apiKey,
      headers: headers,
      httpClient: httpClient,
      timeout: timeout,
      client: client,
      defaultOptions: options,
    );
  }

  @override
  EmbeddingsModel<OmlxEmbeddingsModelOptions> createEmbeddingsModel({
    String? name,
    OmlxEmbeddingsModelOptions? options,
  }) {
    final modelName = name ?? defaultModelNames[ModelKind.embeddings]!;
    _logger.info('Creating oMLX embeddings model: $modelName');

    return OmlxEmbeddingsModel(
      name: modelName,
      baseUrl: baseUrl ?? defaultBaseUrl,
      apiKey: apiKey,
      headers: headers,
      httpClient: httpClient,
      timeout: timeout,
      client: client,
      dimensions: options?.dimensions,
      batchSize: options?.batchSize,
      options: options,
    );
  }

  @override
  MediaGenerationModel<OmlxMediaGenerationModelOptions> createMediaModel({
    String? name,
    List<Tool>? tools,
    OmlxMediaGenerationModelOptions? options,
  }) {
    final modelName =
        name ??
        defaultModelNames[ModelKind.media] ??
        defaultModelNames[ModelKind.tts] ??
        defaultTtsModel;

    _logger.info('Creating oMLX media model: $modelName');

    return OmlxMediaGenerationModel(
      name: modelName,
      tools: tools,
      baseUrl: baseUrl ?? defaultBaseUrl,
      apiKey: apiKey,
      headers: headers,
      httpClient: httpClient,
      timeout: timeout,
      client: client,
      defaultOptions: options,
    );
  }

  @override
  Stream<ModelInfo> listModels() async* {
    _logger.info('Fetching models from oMLX API');
    final response = await _withClient((c) => c.models.list());

    for (final m in response.data) {
      final kinds = OmlxUtils.inferModelKinds(m.id);
      yield ModelInfo(
        name: m.id,
        providerName: name,
        kinds: kinds,
        displayName: m.id,
        extra: {
          if (m.created != null) 'created': m.created,
          if (m.ownedBy != null) 'owned_by': m.ownedBy,
          ...m.extra,
        },
      );
    }
  }

  // --- oMLX Extensions ---

  /// Checks the health and engine pool status of the oMLX server (`GET /health`).
  Future<o.HealthResponse> health() => _withClient((c) => c.health());

  /// Gets detailed engine status for models from the oMLX server
  /// (`GET /v1/models/status`).
  Future<List<o.ModelStatus>> modelsStatus() =>
      _withClient((c) => c.models.status());

  /// Manually unloads/evicts a model from unified memory
  /// (`POST /v1/models/{model_id}/unload`).
  Future<o.UnloadModelResponse> unloadModel(String modelId) =>
      _withClient((c) => c.models.unload(modelId));

  /// Reranks documents based on semantic relevance to a query
  /// (`POST /v1/rerank`).
  Future<List<o.RerankResult>> rerank({
    required String query,
    required List<String> documents,
    String? model,
    int? topN,
    bool returnDocuments = true,
  }) {
    final rerankModel = model ?? 'bge-reranker-large';
    return _withClient(
      (c) => c.rerank.rank(
        model: rerankModel,
        query: query,
        documents: documents,
        topN: topN,
        returnDocuments: returnDocuments,
      ),
    );
  }

  /// Transcribes audio via Whisper (`POST /v1/audio/transcriptions`).
  Future<o.AudioTranscriptionResponse> transcribeAudio(
    o.AudioTranscriptionRequest request,
  ) => _withClient((c) => c.audio.transcribe(request));
}
