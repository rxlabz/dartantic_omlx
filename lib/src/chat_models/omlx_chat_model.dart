import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:domlx/domlx.dart' as o;
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../shared/omlx_utils.dart';
import 'omlx_chat_options.dart';
import 'omlx_message_mappers.dart';

/// Chat model backed by an oMLX server's `/v1/chat/completions` endpoint.
///
/// Streams text, reasoning (`reasoning_content`, surfaced as [ThinkingPart]s),
/// tool calls and usage, including oMLX prefix-cache and timing metrics in the
/// result metadata.
class OmlxChatModel extends ChatModel<OmlxChatOptions> {
  /// Creates an [OmlxChatModel].
  ///
  /// Either pass an existing [client] (which is then not closed by
  /// [dispose]) or let the model create one from [baseUrl], [apiKey],
  /// [headers], [httpClient] and [timeout].
  OmlxChatModel({
    required super.name,
    super.tools,
    super.temperature,
    OmlxChatOptions? defaultOptions,
    this.enableThinking = false,
    Uri? baseUrl,
    String? apiKey,
    Map<String, String>? headers,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 300),
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
       super(defaultOptions: defaultOptions ?? const OmlxChatOptions()) {
    _logger.info(
      'Creating oMLX chat model: $name with ${tools?.length ?? 0} tools, '
      'temp: $temperature, thinking: $enableThinking',
    );
  }

  /// The default oMLX server URL.
  static final defaultBaseUrl = Uri.parse('http://localhost:8000');

  static final Logger _logger = Logger('dartantic.chat.models.omlx');

  final o.OmlxClient _client;
  final bool _ownsClient;

  /// Whether to ask the model's chat template to enable thinking
  /// (`chat_template_kwargs.enable_thinking`). Reasoning content returned by
  /// the server is always surfaced, regardless of this flag.
  final bool enableThinking;

  @override
  Stream<ChatResult<ChatMessage>> sendStream(
    List<ChatMessage> messages, {
    OmlxChatOptions? options,
    Schema? outputSchema,
  }) async* {
    _logger.info(
      'Starting oMLX chat stream with ${messages.length} messages '
      'for model: $name',
    );

    final request = buildChatCompletionRequest(
      messages,
      modelName: name,
      options: defaultOptions.mergeWith(options),
      tools: tools,
      temperature: temperature,
      outputSchema: outputSchema,
      enableThinking: enableThinking,
    );

    final toolCalls = OmlxToolCallAccumulator();
    String? id;
    String? model;
    var finishReason = FinishReason.unspecified;
    o.Usage? usage;
    var chunkCount = 0;

    await for (final chunk in _client.chat.createStream(request)) {
      chunkCount++;
      id ??= chunk.id;
      model = chunk.model;
      if (chunk.usage != null) usage = chunk.usage;

      final choice = chunk.choices.isEmpty ? null : chunk.choices.first;
      if (choice == null) continue;
      if (choice.finishReason != null) {
        finishReason = OmlxUtils.mapFinishReason(choice.finishReason);
      }

      final delta = choice.delta;
      final deltaToolCalls = delta.toolCalls;
      if (deltaToolCalls != null && deltaToolCalls.isNotEmpty) {
        toolCalls.addAll(deltaToolCalls);
      }

      final reasoning = delta.reasoningContent;
      final content = delta.content;
      final parts = <Part>[
        if (reasoning != null && reasoning.isNotEmpty) ThinkingPart(reasoning),
        if (content != null && content.isNotEmpty) TextPart(content),
      ];
      if (parts.isEmpty) continue;

      final message = ChatMessage(role: ChatMessageRole.model, parts: parts);
      yield ChatResult<ChatMessage>(
        id: chunk.id,
        output: message,
        messages: [message],
        thinking: reasoning != null && reasoning.isNotEmpty ? reasoning : null,
        finishReason: FinishReason.unspecified,
      );
    }

    // Final chunk: carries complete tool calls (if any), the finish reason,
    // usage and response-level metadata. Text was already streamed above, so
    // it is not repeated here.
    final finalMessage = ChatMessage(
      role: ChatMessageRole.model,
      parts: toolCalls.isNotEmpty ? toolCalls.build() : const [],
    );
    if (toolCalls.isNotEmpty && finishReason == FinishReason.unspecified) {
      finishReason = FinishReason.toolCalls;
    }

    _logger.info(
      'oMLX chat stream completed after $chunkCount chunks '
      '(finish: $finishReason, usage: ${usage?.totalTokens} tokens)',
    );

    yield ChatResult<ChatMessage>(
      id: id,
      output: finalMessage,
      messages: finalMessage.parts.isEmpty ? const [] : [finalMessage],
      finishReason: finishReason,
      usage: OmlxUtils.mapUsage(usage),
      metadata: {
        'model': ?model,
        ...OmlxUtils.usageMetadata(usage),
      },
    );
  }

  @override
  void dispose() {
    if (_ownsClient) _client.close();
  }
}
