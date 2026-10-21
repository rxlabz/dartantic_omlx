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

    var serverSentReasoning = false;
    var inThinkTag = false;
    var hasFinishedThinkTag = false;
    var hasEmittedNonWhitespaceText = false;
    final tagBuffer = StringBuffer();

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

      if (reasoning != null && reasoning.isNotEmpty) {
        serverSentReasoning = true;
      }

      final parts = <Part>[
        if (reasoning != null && reasoning.isNotEmpty) ThinkingPart(reasoning),
      ];
      final thinkingDeltas = <String>[
        if (reasoning != null && reasoning.isNotEmpty) reasoning,
      ];

      // Parse inline <think>...</think> only when the server does not already
      // separate reasoning into delta.reasoningContent, and only before any
      // user-visible answer text has started. Once normal text starts or
      // </think> finishes, any <think> in content is literal text.
      if (content != null && content.isNotEmpty) {
        if (serverSentReasoning ||
            hasFinishedThinkTag ||
            hasEmittedNonWhitespaceText) {
          parts.add(TextPart(content));
          if (content.trim().isNotEmpty) {
            hasEmittedNonWhitespaceText = true;
          }
        } else {
          tagBuffer.write(content);
          var currentText = tagBuffer.toString();
          tagBuffer.clear();

          while (currentText.isNotEmpty) {
            if (!inThinkTag) {
              final thinkStart = currentText.indexOf('<think>');
              if (thinkStart != -1) {
                final before = currentText.substring(0, thinkStart);
                if (before.trim().isEmpty) {
                  // Discard leading whitespace before <think>
                  inThinkTag = true;
                  var after = currentText.substring(
                    thinkStart + '<think>'.length,
                  );
                  // Strip a single leading newline if present immediately after <think>
                  if (after.startsWith('\r\n')) {
                    after = after.substring(2);
                  } else if (after.startsWith('\n')) {
                    after = after.substring(1);
                  }
                  currentText = after;
                } else {
                  // Non-whitespace text appeared before <think>; treat as literal text
                  parts.add(TextPart(currentText));
                  hasEmittedNonWhitespaceText = true;
                  currentText = '';
                }
              } else {
                // Check if trailing chars form a prefix of '<think>'
                final potentialPrefix = _findPotentialTagPrefix(
                  currentText,
                  '<think>',
                );
                if (potentialPrefix.isNotEmpty) {
                  final safeLength = currentText.length - potentialPrefix.length;
                  if (safeLength > 0) {
                    final safeText = currentText.substring(0, safeLength);
                    if (safeText.trim().isNotEmpty) {
                      parts.add(TextPart(safeText));
                      hasEmittedNonWhitespaceText = true;
                      parts.add(TextPart(potentialPrefix));
                      currentText = '';
                      continue;
                    } else {
                      tagBuffer.write(currentText);
                      currentText = '';
                      continue;
                    }
                  } else {
                    tagBuffer.write(potentialPrefix);
                    currentText = '';
                  }
                } else {
                  parts.add(TextPart(currentText));
                  if (currentText.trim().isNotEmpty) {
                    hasEmittedNonWhitespaceText = true;
                  }
                  currentText = '';
                }
              }
            } else {
              // Currently inside <think>
              final thinkEnd = currentText.indexOf('</think>');
              if (thinkEnd != -1) {
                if (thinkEnd > 0) {
                  var thinkText = currentText.substring(0, thinkEnd);
                  if (thinkText.endsWith('\r\n')) {
                    thinkText = thinkText.substring(0, thinkText.length - 2);
                  } else if (thinkText.endsWith('\n')) {
                    thinkText = thinkText.substring(0, thinkText.length - 1);
                  }
                  if (thinkText.isNotEmpty) {
                    parts.add(ThinkingPart(thinkText));
                    thinkingDeltas.add(thinkText);
                  }
                }
                inThinkTag = false;
                hasFinishedThinkTag = true;
                var after = currentText.substring(thinkEnd + '</think>'.length);
                // Strip leading newlines if present immediately after </think>
                if (after.startsWith('\r\n\r\n')) {
                  after = after.substring(4);
                } else if (after.startsWith('\n\n')) {
                  after = after.substring(2);
                } else if (after.startsWith('\r\n')) {
                  after = after.substring(2);
                } else if (after.startsWith('\n')) {
                  after = after.substring(1);
                }
                currentText = after;
              } else {
                // Check if trailing chars form a prefix of '</think>'
                final potentialPrefix = _findPotentialTagPrefix(
                  currentText,
                  '</think>',
                );
                if (potentialPrefix.isNotEmpty) {
                  final safeLength =
                      currentText.length - potentialPrefix.length;
                  if (safeLength > 0) {
                    final thinkText = currentText.substring(0, safeLength);
                    parts.add(ThinkingPart(thinkText));
                    thinkingDeltas.add(thinkText);
                  }
                  tagBuffer.write(potentialPrefix);
                  currentText = '';
                } else {
                  parts.add(ThinkingPart(currentText));
                  thinkingDeltas.add(currentText);
                  currentText = '';
                }
              }
            }
          }
        }
      }

      if (parts.isEmpty) continue;

      final message = ChatMessage(role: ChatMessageRole.model, parts: parts);
      yield ChatResult<ChatMessage>(
        id: chunk.id,
        output: message,
        messages: [message],
        thinking: thinkingDeltas.isNotEmpty ? thinkingDeltas.join() : null,
        finishReason: FinishReason.unspecified,
      );
    }

    // Flush any leftover buffered characters in tagBuffer
    if (tagBuffer.isNotEmpty) {
      final leftover = tagBuffer.toString();
      tagBuffer.clear();
      final part = inThinkTag ? ThinkingPart(leftover) : TextPart(leftover);
      final message = ChatMessage(role: ChatMessageRole.model, parts: [part]);
      yield ChatResult<ChatMessage>(
        id: id ?? '',
        output: message,
        messages: [message],
        thinking: inThinkTag ? leftover : null,
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

  /// Checks if the end of [text] matches a prefix of [tag].
  /// Returns the matching prefix, or an empty string if none.
  static String _findPotentialTagPrefix(String text, String tag) {
    final maxCheck = text.length < tag.length ? text.length : tag.length - 1;
    for (var len = maxCheck; len > 0; len--) {
      final suffix = text.substring(text.length - len);
      if (tag.startsWith(suffix)) {
        return suffix;
      }
    }
    return '';
  }
}
