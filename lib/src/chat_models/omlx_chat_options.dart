import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:domlx/domlx.dart' as o show ResponseFormat;
import 'package:meta/meta.dart';

export 'package:domlx/domlx.dart' show ResponseFormat, ToolChoice;

/// Options for oMLX chat completions (`/v1/chat/completions`).
@immutable
class OmlxChatOptions extends ChatModelOptions {
  /// Creates a new set of oMLX chat options.
  const OmlxChatOptions({
    this.temperature,
    this.topP,
    this.topK,
    this.repetitionPenalty,
    this.maxTokens,
    this.responseFormat,
    this.toolChoice,
    this.stop,
    this.user,
    this.includeUsage,
    this.chatTemplateKwargs,
    this.extra,
  });

  /// Sampling temperature.
  final double? temperature;

  /// Nucleus sampling probability threshold.
  final double? topP;

  /// Top-K sampling cutoff.
  final int? topK;

  /// Repetition penalty factor.
  final double? repetitionPenalty;

  /// Maximum number of tokens to generate.
  final int? maxTokens;

  /// Structured output configuration.
  ///
  /// Ignored when an `outputSchema` is passed to `sendStream`, which takes
  /// precedence.
  final o.ResponseFormat? responseFormat;

  /// Controls which tool is called: `'auto'`, `'none'`, `'required'` or a
  /// specific function (see `ToolChoice.function`).
  final Object? toolChoice;

  /// Stop sequences.
  final List<String>? stop;

  /// End-user identifier.
  final String? user;

  /// Whether to request usage statistics in the final streaming chunk via
  /// `stream_options.include_usage`. Defaults to `true`.
  final bool? includeUsage;

  /// Additional arguments passed directly to the model's HuggingFace Jinja chat template
  /// via `chat_template_kwargs` (e.g. `{'enable_thinking': false}`).
  final Map<String, dynamic>? chatTemplateKwargs;

  /// Additional oMLX or vendor-specific request parameters, merged into the
  /// request body (e.g. `{'repetition_context_size': 20}`).
  final Map<String, dynamic>? extra;

  /// Returns a copy where each field of [other] that is non-null overrides
  /// the corresponding field of this instance.
  OmlxChatOptions mergeWith(OmlxChatOptions? other) {
    if (other == null) return this;
    return OmlxChatOptions(
      temperature: other.temperature ?? temperature,
      topP: other.topP ?? topP,
      topK: other.topK ?? topK,
      repetitionPenalty: other.repetitionPenalty ?? repetitionPenalty,
      maxTokens: other.maxTokens ?? maxTokens,
      responseFormat: other.responseFormat ?? responseFormat,
      toolChoice: other.toolChoice ?? toolChoice,
      stop: other.stop ?? stop,
      user: other.user ?? user,
      includeUsage: other.includeUsage ?? includeUsage,
      chatTemplateKwargs: {
        ...?chatTemplateKwargs,
        ...?other.chatTemplateKwargs,
      },
      extra: {...?extra, ...?other.extra},
    );
  }
}
