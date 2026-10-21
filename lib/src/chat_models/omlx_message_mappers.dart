import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:domlx/domlx.dart' as o;
import 'package:logging/logging.dart';

import '../shared/omlx_utils.dart';
import 'omlx_chat_options.dart';

final Logger _logger = Logger('dartantic.chat.mappers.omlx');

/// Builds an oMLX [o.ChatCompletionRequest] from dartantic inputs.
o.ChatCompletionRequest buildChatCompletionRequest(
  List<ChatMessage> messages, {
  required String modelName,
  required OmlxChatOptions options,
  List<Tool>? tools,
  double? temperature,
  Schema? outputSchema,
  bool enableThinking = false,
}) {
  final chatTemplateKwargs = <String, dynamic>{
    'enable_thinking': enableThinking,
    ...?options.chatTemplateKwargs,
  };

  // Merge extra parameters if options.extra has chat_template_kwargs
  final extraMap = Map<String, dynamic>.from(options.extra ?? const {});
  final rawExtraChatKwargs = extraMap.remove('chat_template_kwargs');
  if (rawExtraChatKwargs is Map) {
    chatTemplateKwargs.addAll(Map<String, dynamic>.from(rawExtraChatKwargs));
  }

  // Handle stream_options merging if present in extraMap
  final streamOptions = <String, dynamic>{
    if (options.includeUsage ?? true) 'include_usage': true,
  };
  final rawExtraStreamOptions = extraMap.remove('stream_options');
  if (rawExtraStreamOptions is Map) {
    streamOptions.addAll(Map<String, dynamic>.from(rawExtraStreamOptions));
  }

  final extra = <String, dynamic>{
    if (streamOptions.isNotEmpty) 'stream_options': streamOptions,
    'chat_template_kwargs': chatTemplateKwargs,
    ...extraMap,
  };

  return o.ChatCompletionRequest(
    model: modelName,
    messages: messages.toOmlxMessages(),
    temperature: options.temperature ?? temperature,
    topP: options.topP,
    topK: options.topK,
    repetitionPenalty: options.repetitionPenalty,
    maxTokens: options.maxTokens,
    tools: tools == null || tools.isEmpty ? null : tools.toOmlxTools(),
    toolChoice: tools == null || tools.isEmpty ? null : options.toolChoice,
    responseFormat: outputSchema != null
        ? o.ResponseFormat.jsonSchema(
            name: 'output_schema',
            description: 'Generated response following the provided schema',
            schema: prepareSchemaForOmlx(
              Map<String, dynamic>.from(outputSchema.value),
              strict: true,
            ),
            strict: true,
          )
        : options.responseFormat,
    stop: options.stop,
    user: options.user,
    extra: extra,
  );
}

/// Converts dartantic [Tool]s to oMLX tool definitions.
extension OmlxToolListMapper on List<Tool> {
  /// Converts this list into oMLX [o.Tool] function definitions.
  List<o.Tool> toOmlxTools() => map(
    (tool) => o.Tool.function(
      name: tool.name,
      description: tool.description,
      parameters: prepareSchemaForOmlx(
        Map<String, dynamic>.from(tool.inputSchema.value),
        strict: false,
      ),
    ),
  ).toList(growable: false);
}

/// Recursively prepares and normalizes a JSON Schema for oMLX (OpenAI-compatible)
/// tool parameters and structured output definitions.
///
/// Ensures:
/// - Nested objects always have a `properties` map.
/// - When [strict] is `true`: `additionalProperties: false` is added to all
///   object nodes, and all properties are required.
/// - Incompatible nullable type arrays (e.g. `['string', 'null']`) are flattened.
/// - Unsupported format constraints are removed.
Map<String, dynamic> prepareSchemaForOmlx(
  Map<String, dynamic> schema, {
  bool strict = false,
}) {
  final result = Map<String, dynamic>.from(schema);

  // Flatten nullable types (e.g. ['string', 'null'] -> 'string') only for non-strict tool schemas
  if (!strict && result['type'] is List) {
    final types = result['type'] as List;
    final nonNullTypes = types.where((t) => t != 'null').toList();
    if (nonNullTypes.length == 1) {
      result['type'] = nonNullTypes.first;
    }
  }

  // Remove format field if present
  result.remove('format');

  // If this is an object, ensure properties map, additionalProperties, and required
  final typeVal = result['type'];
  final isObject = typeVal == 'object' ||
      (typeVal is List && typeVal.contains('object')) ||
      (typeVal == null && result.containsKey('properties'));

  if (isObject) {
    if (strict) {
      result['additionalProperties'] = false;
    }

    final properties = result['properties'] as Map<String, dynamic>?;
    final originalRequired =
        (result['required'] as List?)?.cast<String>().toSet() ?? <String>{};

    if (properties != null && properties.isNotEmpty) {
      final processedProperties = <String, dynamic>{};
      for (final entry in properties.entries) {
        if (entry.value is Map) {
          var propSchema = Map<String, dynamic>.from(entry.value as Map);
          if (strict && !originalRequired.contains(entry.key)) {
            // In strict mode, properties not originally in required must allow null
            if (propSchema['type'] is String && propSchema['type'] != 'null') {
              propSchema['type'] = [propSchema['type'], 'null'];
            } else if (propSchema['type'] is List) {
              final types = (propSchema['type'] as List).toList();
              if (!types.contains('null')) {
                types.add('null');
                propSchema['type'] = types;
              }
            } else if (propSchema['anyOf'] != null) {
              final anyOf = (propSchema['anyOf'] as List).toList();
              if (!anyOf.any((item) => item is Map && item['type'] == 'null')) {
                anyOf.add({'type': 'null'});
                propSchema['anyOf'] = anyOf;
              }
            }
          }
          processedProperties[entry.key] = prepareSchemaForOmlx(
            propSchema,
            strict: strict,
          );
        } else {
          processedProperties[entry.key] = entry.value;
        }
      }
      result['properties'] = processedProperties;

      if (strict) {
        result['required'] = properties.keys.toList();
      } else if (result.containsKey('required')) {
        result['required'] = originalRequired.toList();
      }
    } else {
      result['properties'] = <String, dynamic>{};
      if (strict) {
        result['required'] = <String>[];
      }
    }
  }

  // Process array items
  final isArray = typeVal == 'array' ||
      (typeVal is List && typeVal.contains('array'));
  if (isArray) {
    final items = result['items'];
    if (items is Map) {
      result['items'] = prepareSchemaForOmlx(
        Map<String, dynamic>.from(items),
        strict: strict,
      );
    }
  }

  // Process definitions/$defs if present
  final definitions = result[r'$defs'] ?? result['definitions'];
  final defKey = result.containsKey(r'$defs') ? r'$defs' : 'definitions';
  if (definitions is Map) {
    final processedDefs = <String, dynamic>{};
    for (final entry in definitions.entries) {
      if (entry.value is Map) {
        processedDefs[entry.key as String] = prepareSchemaForOmlx(
          Map<String, dynamic>.from(entry.value as Map),
          strict: strict,
        );
      } else {
        processedDefs[entry.key as String] = entry.value;
      }
    }
    result[defKey] = processedDefs;
  }

  // Process polymorphic / composition keywords: anyOf, oneOf, allOf
  for (final key in const ['anyOf', 'oneOf', 'allOf']) {
    final list = result[key];
    if (list is List) {
      result[key] = list.map((item) {
        if (item is Map) {
          return prepareSchemaForOmlx(
            Map<String, dynamic>.from(item),
            strict: strict,
          );
        }
        return item;
      }).toList();
    }
  }

  return result;
}

/// Converts dartantic [ChatMessage]s to oMLX chat messages.
extension OmlxMessageListMapper on List<ChatMessage> {
  /// Converts this conversation into oMLX [o.ChatMessage]s.
  ///
  /// Tool results are expanded into one `tool` role message per result.
  /// [ThinkingPart]s are preserved as `reasoningContent` on messages that
  /// contain tool calls or the most recent model message, but omitted on
  /// past completed turns to prevent prompt bloat and template errors.
  List<o.ChatMessage> toOmlxMessages() {
    _logger.fine('Converting $length messages to oMLX format');
    final result = <o.ChatMessage>[];
    for (var i = 0; i < length; i++) {
      final message = this[i];
      switch (message.role) {
        case ChatMessageRole.system:
          result.add(o.ChatMessage.system(message.text));
        case ChatMessageRole.user:
          result.addAll(_mapUserMessage(message));
        case ChatMessageRole.model:
          final isRecentOrHasTools = message.hasToolCalls || i == length - 1;
          result.add(
            _mapModelMessage(message, includeReasoning: isRecentOrHasTools),
          );
      }
    }
    return result;
  }
}

List<o.ChatMessage> _mapUserMessage(ChatMessage message) {
  final toolResults = message.toolResults;
  final messages = <o.ChatMessage>[
    for (final toolResult in toolResults)
      o.ChatMessage.tool(
        toolCallId: toolResult.callId,
        content: OmlxUtils.serializeToolResult(toolResult.result),
      ),
  ];

  final contentParts = <o.ContentPart>[];
  for (final part in message.parts) {
    switch (part) {
      case TextPart(:final text):
        contentParts.add(o.ContentPart.text(text));
      case DataPart(:final bytes, :final mimeType):
        final dataUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';
        contentParts.add(
          mimeType.startsWith('image/')
              ? o.ContentPart.imageUrl(dataUrl)
              : o.ContentPart.text('[media: $mimeType] $dataUrl'),
        );
      case LinkPart(:final url, :final mimeType):
        contentParts.add(
          (mimeType?.startsWith('image/') ?? false)
              ? o.ContentPart.imageUrl(url.toString())
              : o.ContentPart.text(url.toString()),
        );
      case ToolPart():
      case ThinkingPart():
        break;
    }
  }

  if (contentParts.isNotEmpty) {
    if (contentParts.length == 1 && contentParts.first is o.TextContentPart) {
      messages.add(
        o.ChatMessage.user((contentParts.first as o.TextContentPart).text),
      );
    } else if (contentParts.every((p) => p is o.TextContentPart)) {
      messages.add(
        o.ChatMessage.user(
          contentParts.cast<o.TextContentPart>().map((p) => p.text).join('\n'),
        ),
      );
    } else {
      messages.add(o.ChatMessage.userParts(contentParts));
    }
  } else if (toolResults.isEmpty) {
    messages.add(o.ChatMessage.user(''));
  }

  return messages;
}

o.ChatMessage _mapModelMessage(
  ChatMessage message, {
  bool includeReasoning = true,
}) {
  final text = message.text;
  final thinkingParts = message.parts.whereType<ThinkingPart>().toList();
  final reasoningContent = (includeReasoning && thinkingParts.isNotEmpty)
      ? thinkingParts.map((p) => p.text).join()
      : null;

  final toolCalls = message.toolCalls
      .map(
        (p) => o.ToolCall(
          id: p.callId,
          function: o.FunctionCall(
            name: p.toolName,
            arguments: jsonEncode(p.arguments ?? const <String, Object?>{}),
          ),
        ),
      )
      .toList(growable: false);

  return o.ChatMessage.assistant(
    text.isEmpty ? null : text,
    reasoningContent: reasoningContent,
    toolCalls: toolCalls.isEmpty ? null : toolCalls,
  );
}

/// Accumulates streamed tool call deltas into complete tool calls.
///
/// OpenAI-compatible servers stream a tool call as a first delta carrying the
/// `id`, `index` and `name`, followed by deltas carrying argument fragments
/// (keyed by `index`, usually without `id`). Some servers send each tool call
/// in a single delta, possibly without `index`.
class OmlxToolCallAccumulator {
  final List<_PendingToolCall> _calls = [];

  /// Whether any tool call has been accumulated.
  bool get isNotEmpty => _calls.isNotEmpty;

  /// Adds the tool call deltas of a single chunk.
  void addAll(List<o.ToolCall> deltas) {
    for (final delta in deltas) {
      _add(delta);
    }
  }

  void _add(o.ToolCall delta) {
    final id = delta.id;
    final name = delta.function.name;
    final args = delta.function.arguments;

    _PendingToolCall? existing;
    if (delta.index != null) {
      existing = _calls.where((c) => c.index == delta.index).lastOrNull;
    } else if (id != null && id.isNotEmpty) {
      existing = _calls.where((c) => c.id == id).lastOrNull;
    } else if (name.isEmpty && _calls.isNotEmpty) {
      // Continuation without id/index: append to the last call.
      existing = _calls.last;
    }

    // A new id on an already-used index means a new call (some servers reuse
    // index 0 for every call).
    if (existing != null &&
        id != null &&
        id.isNotEmpty &&
        existing.id != null &&
        existing.id != id) {
      existing = null;
    }

    if (existing == null) {
      _calls.add(
        _PendingToolCall(
          index: delta.index ?? _calls.length,
          id: id == null || id.isEmpty ? null : id,
          name: name,
        )..arguments.write(args),
      );
      return;
    }

    if (existing.id == null && id != null && id.isNotEmpty) existing.id = id;
    if (name.isNotEmpty) existing.name = name;
    existing.arguments.write(args);
  }

  /// Builds the final [ToolPart] calls.
  List<ToolPart> build() => [
    for (final call in _calls)
      ToolPart.call(
        callId: call.id ?? OmlxUtils.generateToolCallId(),
        toolName: call.name,
        arguments: _decodeArguments(call.arguments.toString()),
      ),
  ];
}

class _PendingToolCall {
  _PendingToolCall({required this.index, required this.id, required this.name});

  final int index;
  String? id;
  String name;
  final StringBuffer arguments = StringBuffer();
}

Map<String, Object?> _decodeArguments(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed == 'null' || trimmed == '""') return {};
  final decoded = jsonDecode(trimmed);
  if (decoded is Map) return decoded.cast<String, Object?>();
  if (decoded == null || decoded == 'null') return {};
  throw FormatException('Tool call arguments are not a JSON object', raw);
}

/// Converts a non-streamed oMLX assistant message into a dartantic message.
ChatMessage chatMessageFromOmlx(o.ChatMessage message) {
  final parts = <Part>[];
  var reasoning = message.reasoningContent;
  var text = message.textContent;

  // If reasoningContent was not separated by the server, extract from inline <think> if present
  // at the start of the message (ignoring optional leading whitespace).
  if ((reasoning == null || reasoning.isEmpty) &&
      text.contains('<think>') &&
      text.contains('</think>')) {
    final thinkStart = text.indexOf('<think>');
    final thinkEnd = text.indexOf('</think>');
    if (thinkStart < thinkEnd && text.substring(0, thinkStart).trim().isEmpty) {
      var think = text.substring(thinkStart + '<think>'.length, thinkEnd);
      var after = text.substring(thinkEnd + '</think>'.length);
      if (think.startsWith('\r\n')) {
        think = think.substring(2);
      } else if (think.startsWith('\n')) {
        think = think.substring(1);
      }
      if (think.endsWith('\r\n')) {
        think = think.substring(0, think.length - 2);
      } else if (think.endsWith('\n')) {
        think = think.substring(0, think.length - 1);
      }
      if (after.startsWith('\r\n\r\n')) {
        after = after.substring(4);
      } else if (after.startsWith('\n\n')) {
        after = after.substring(2);
      } else if (after.startsWith('\r\n')) {
        after = after.substring(2);
      } else if (after.startsWith('\n')) {
        after = after.substring(1);
      }
      reasoning = think;
      text = after;
    }
  }

  if (reasoning != null && reasoning.isNotEmpty) {
    parts.add(ThinkingPart(reasoning));
  }
  if (text.isNotEmpty) parts.add(TextPart(text));
  final toolCalls = message.toolCalls;
  if (toolCalls != null && toolCalls.isNotEmpty) {
    parts.addAll((OmlxToolCallAccumulator()..addAll(toolCalls)).build());
  }
  return ChatMessage(role: ChatMessageRole.model, parts: parts);
}
