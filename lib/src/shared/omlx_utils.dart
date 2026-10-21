import 'dart:convert';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:domlx/domlx.dart' as o;
import 'package:uuid/uuid.dart';

import 'env_stub.dart' if (dart.library.io) 'env_io.dart' as env;

/// Shared helpers for the oMLX provider.
abstract final class OmlxUtils {
  static const _uuid = Uuid();

  /// Default base URL for oMLX server (`http://localhost:8000`).
  static final defaultBaseUrl = Uri.parse('http://localhost:8000');

  /// Resolves the oMLX base URL by checking:
  /// 1. An explicitly provided [baseUrl]
  /// 2. `OMLX_BASE_URL` environment variable
  /// 3. `OMLX_HOST` environment variable
  /// 4. [defaultBaseUrl] (`http://localhost:8000`)
  static Uri resolveBaseUrl([Uri? baseUrl]) {
    if (baseUrl != null) return baseUrl;
    final envVal = tryGetEnv('OMLX_BASE_URL') ?? tryGetEnv('OMLX_HOST');
    if (envVal != null && envVal.trim().isNotEmpty) {
      final trimmed = envVal.trim();
      final withScheme =
          (trimmed.startsWith('http://') || trimmed.startsWith('https://'))
              ? trimmed
              : 'http://$trimmed';
      final parsed = Uri.tryParse(withScheme);
      if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
        return parsed;
      }
    }
    return defaultBaseUrl;
  }

  /// Generates a unique tool call ID for servers that omit one.
  static String generateToolCallId() => _uuid.v4();

  /// Looks up an environment variable, first in [Agent.environment] and then
  /// (unless [Agent.useAgentEnvironmentOnly] is set) in the platform
  /// environment.
  static String? tryGetEnv(String? name) {
    if (name == null || name.isEmpty) return null;
    final fromAgent = Agent.environment[name];
    if (fromAgent != null && fromAgent.isNotEmpty) return fromAgent;
    if (Agent.useAgentEnvironmentOnly) return null;
    final value = env.platformEnv(name);
    return value == null || value.isEmpty ? null : value;
  }

  /// Serializes a tool result into the string form expected by the
  /// OpenAI-compatible `tool` role message.
  static String serializeToolResult(Object? result) =>
      result is String ? result : jsonEncode(result);

  /// Maps an OpenAI-compatible finish reason string to [FinishReason].
  static FinishReason mapFinishReason(String? reason) => switch (reason) {
    null => FinishReason.unspecified,
    'stop' || 'end_turn' => FinishReason.stop,
    'length' || 'max_tokens' => FinishReason.length,
    'tool_calls' || 'function_call' || 'tool_use' => FinishReason.toolCalls,
    'content_filter' => FinishReason.contentFilter,
    _ => FinishReason.unspecified,
  };

  /// Maps oMLX [o.Usage] to [LanguageModelUsage].
  static LanguageModelUsage? mapUsage(o.Usage? usage) {
    if (usage == null) return null;
    return LanguageModelUsage(
      promptTokens: usage.promptTokens,
      responseTokens: usage.completionTokens,
      totalTokens: usage.totalTokens,
    );
  }

  /// Extracts oMLX-specific usage extensions (prefix cache and timings) as
  /// result metadata.
  static Map<String, dynamic> usageMetadata(o.Usage? usage) {
    if (usage == null) return const {};
    final cached = usage.cachedTokens ?? usage.promptTokensDetails?.cachedTokens;
    return {
      'cached_tokens': ?cached,
      'prefill_duration': ?usage.prefillDuration,
      'generation_duration': ?usage.generationDuration,
    };
  }

  /// Infers model kinds from an oMLX model id.
  static Set<ModelKind> inferModelKinds(String id) {
    final lower = id.toLowerCase();
    final kinds = <ModelKind>{};

    if (lower.contains('rerank')) {
      kinds.add(ModelKind.other);
    } else if (lower.contains('embed') ||
        lower.contains('bge-') ||
        lower.contains('e5-') ||
        lower.contains('minilm') ||
        lower.contains('nomic')) {
      kinds.add(ModelKind.embeddings);
    }
    if (lower.contains('tts') ||
        lower.contains('kokoro') ||
        lower.contains('speech')) {
      kinds
        ..add(ModelKind.tts)
        ..add(ModelKind.media);
    }
    if (lower.contains('whisper') || lower.contains('stt')) {
      kinds.add(ModelKind.audio);
    }
    if (lower.contains('-vl') ||
        lower.contains('vision') ||
        lower.contains('llava') ||
        lower.contains('pixtral')) {
      kinds
        ..add(ModelKind.image)
        ..add(ModelKind.chat);
    }

    if (kinds.isEmpty) kinds.add(ModelKind.chat);
    return kinds;
  }
}
