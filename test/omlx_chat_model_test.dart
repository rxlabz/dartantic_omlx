import 'dart:convert';

import 'package:dartantic_omlx/dartantic_omlx.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('OmlxChatModel', () {
    test('streams plain text chunks and terminal usage', () async {
      final sseLines = [
        ': keep-alive\n\n',
        'data: ${jsonEncode({
          'id': 'chatcmpl-1',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'qwen',
          'choices': [
            {
              'index': 0,
              'delta': {'role': 'assistant', 'content': 'Hello'},
              'finish_reason': null,
            }
          ],
        })}\n\n',
        'data: ${jsonEncode({
          'id': 'chatcmpl-1',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'qwen',
          'choices': [
            {
              'index': 0,
              'delta': {'content': ' world!'},
              'finish_reason': null,
            }
          ],
        })}\n\n',
        'data: ${jsonEncode({
          'id': 'chatcmpl-1',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'qwen',
          'choices': [
            {
              'index': 0,
              'delta': <String, dynamic>{},
              'finish_reason': 'stop',
            }
          ],
          'usage': {
            'prompt_tokens': 10,
            'completion_tokens': 2,
            'total_tokens': 12,
            'cached_tokens': 5,
            'prefill_duration': 0.12,
            'generation_duration': 0.05,
          },
        })}\n\n',
        'data: [DONE]\n\n',
      ];

      final mock = MockClient.streaming((request, bodyStream) async {
        expect(request.url.path, '/v1/chat/completions');
        return http.StreamedResponse(
          Stream.fromIterable(sseLines.map(utf8.encode)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final model = OmlxChatModel(
        name: 'qwen',
        httpClient: mock,
      );

      final results = await model.sendStream([
        ChatMessage.user('Hi'),
      ]).toList();

      expect(results.length, 3);

      // Chunk 1
      expect(results[0].output.text, 'Hello');
      expect(results[0].finishReason, FinishReason.unspecified);

      // Chunk 2
      expect(results[1].output.text, ' world!');
      expect(results[1].finishReason, FinishReason.unspecified);

      // Terminal chunk
      expect(results[2].finishReason, FinishReason.stop);
      expect(results[2].usage?.promptTokens, 10);
      expect(results[2].usage?.responseTokens, 2);
      expect(results[2].usage?.totalTokens, 12);
      expect(results[2].metadata['cached_tokens'], 5);
      expect(results[2].metadata['prefill_duration'], 0.12);
      expect(results[2].metadata['generation_duration'], 0.05);
    });

    test('streams reasoning content as ThinkingPart and thinking delta', () async {
      final sseLines = [
        'data: ${jsonEncode({
          'id': 'chatcmpl-think',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'deepseek-r1',
          'choices': [
            {
              'index': 0,
              'delta': {
                'role': 'assistant',
                'reasoning_content': 'Thinking about 9801...',
              },
              'finish_reason': null,
            }
          ],
        })}\n\n',
        'data: ${jsonEncode({
          'id': 'chatcmpl-think',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'deepseek-r1',
          'choices': [
            {
              'index': 0,
              'delta': {'content': 'The square root is 99.'},
              'finish_reason': 'stop',
            }
          ],
        })}\n\n',
        'data: [DONE]\n\n',
      ];

      final mock = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.fromIterable(sseLines.map(utf8.encode)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final model = OmlxChatModel(
        name: 'deepseek-r1',
        enableThinking: true,
        httpClient: mock,
      );

      final results = await model.sendStream([
        ChatMessage.user('Sqrt of 9801?'),
      ]).toList();

      expect(results.length, 3);
      // Chunk 1 has ThinkingPart
      expect(results[0].thinking, 'Thinking about 9801...');
      expect(
        results[0].output.parts.whereType<ThinkingPart>().first.text,
        'Thinking about 9801...',
      );

      // Chunk 2 has TextPart
      expect(results[1].output.text, 'The square root is 99.');

      // Chunk 3 is final stop
      expect(results[2].finishReason, FinishReason.stop);
    });

    test('extracts inline <think>...</think> tags in delta.content', () async {
      final sseLines = [
        'data: ${jsonEncode({
          'id': 'chatcmpl-inline',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'qwen',
          'choices': [
            {
              'index': 0,
              'delta': {
                'role': 'assistant',
                'content': '<th',
              },
              'finish_reason': null,
            }
          ],
        })}\n\n',
        'data: ${jsonEncode({
          'id': 'chatcmpl-inline',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'qwen',
          'choices': [
            {
              'index': 0,
              'delta': {
                'content': 'ink>Internal thought process</think>Final answer.',
              },
              'finish_reason': 'stop',
            }
          ],
        })}\n\n',
        'data: [DONE]\n\n',
      ];

      final mock = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.fromIterable(sseLines.map(utf8.encode)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final model = OmlxChatModel(
        name: 'qwen',
        enableThinking: true,
        httpClient: mock,
      );

      final results = await model.sendStream([
        ChatMessage.user('Question'),
      ]).toList();

      // Chunk 1 ('<th') was buffered because it was a potential prefix of '<think>'
      // Chunk 2 completed '<think>', extracted 'Internal thought process' as ThinkingPart and 'Final answer.' as TextPart
      final thinkingParts = results
          .expand((r) => r.output.parts)
          .whereType<ThinkingPart>()
          .toList();
      final textParts = results
          .expand((r) => r.output.parts)
          .whereType<TextPart>()
          .toList();

      expect(thinkingParts.length, 1);
      expect(thinkingParts.first.text, 'Internal thought process');

      expect(textParts.length, 1);
      expect(textParts.first.text, 'Final answer.');

      final thinkingDeltas = results.map((r) => r.thinking).whereType<String>().toList();
      expect(thinkingDeltas.join(), 'Internal thought process');
    });

    test('strips leading newline after <think> and discards whitespace before <think>', () async {
      final sseLines = [
        'data: ${jsonEncode({
          'id': 'chatcmpl-newline',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'qwen',
          'choices': [
            {
              'index': 0,
              'delta': {'role': 'assistant', 'content': '\n<think>\nThought line 1\nThought line 2</think>\n\nAnswer line.'},
              'finish_reason': 'stop',
            }
          ],
        })}\n\n',
        'data: [DONE]\n\n',
      ];

      final mock = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.fromIterable(sseLines.map(utf8.encode)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final model = OmlxChatModel(
        name: 'qwen',
        enableThinking: true,
        httpClient: mock,
      );

      final results = await model.sendStream([
        ChatMessage.user('Question'),
      ]).toList();

      final thinkingParts = results
          .expand((r) => r.output.parts)
          .whereType<ThinkingPart>()
          .toList();
      final textParts = results
          .expand((r) => r.output.parts)
          .whereType<TextPart>()
          .toList();

      expect(thinkingParts.length, 1);
      expect(thinkingParts.first.text, 'Thought line 1\nThought line 2');

      expect(textParts.length, 1);
      expect(textParts.first.text, 'Answer line.');
    });

    test('buffers leading whitespace chunk before <think> and discards it when <think> arrives', () async {
      final sseLines = [
        'data: ${jsonEncode({
          'id': 'chatcmpl-ws',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'qwen',
          'choices': [
            {
              'index': 0,
              'delta': {'role': 'assistant', 'content': '\n\n'},
              'finish_reason': null,
            }
          ],
        })}\n\n',
        'data: ${jsonEncode({
          'id': 'chatcmpl-ws',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'qwen',
          'choices': [
            {
              'index': 0,
              'delta': {'content': '<think>Deep thought</think>Direct answer.'},
              'finish_reason': 'stop',
            }
          ],
        })}\n\n',
        'data: [DONE]\n\n',
      ];

      final mock = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.fromIterable(sseLines.map(utf8.encode)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final model = OmlxChatModel(
        name: 'qwen',
        enableThinking: true,
        httpClient: mock,
      );

      final results = await model.sendStream([
        ChatMessage.user('Question'),
      ]).toList();

      // Chunk 1 ('\n\n') should not have emitted any text part
      final thinkingParts = results
          .expand((r) => r.output.parts)
          .whereType<ThinkingPart>()
          .toList();
      final textParts = results
          .expand((r) => r.output.parts)
          .whereType<TextPart>()
          .toList();

      expect(thinkingParts.length, 1);
      expect(thinkingParts.first.text, 'Deep thought');

      expect(textParts.length, 1);
      expect(textParts.first.text, 'Direct answer.');

      // The first result should be thinking, NOT a leading whitespace TextPart
      expect(results.first.output.parts.first, isA<ThinkingPart>());
    });

    test('preserves leading whitespace when followed by non-think text across chunks', () async {
      final sseLines = [
        'data: ${jsonEncode({
          'id': 'chatcmpl-ws2',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'qwen',
          'choices': [
            {
              'index': 0,
              'delta': {'role': 'assistant', 'content': '\n'},
              'finish_reason': null,
            }
          ],
        })}\n\n',
        'data: ${jsonEncode({
          'id': 'chatcmpl-ws2',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'qwen',
          'choices': [
            {
              'index': 0,
              'delta': {'content': 'Hello world'},
              'finish_reason': 'stop',
            }
          ],
        })}\n\n',
        'data: [DONE]\n\n',
      ];

      final mock = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.fromIterable(sseLines.map(utf8.encode)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final model = OmlxChatModel(
        name: 'qwen',
        enableThinking: true,
        httpClient: mock,
      );

      final results = await model.sendStream([
        ChatMessage.user('Question'),
      ]).toList();

      final textParts = results
          .expand((r) => r.output.parts)
          .whereType<TextPart>()
          .toList();

      expect(textParts.length, 1);
      expect(textParts.first.text, '\nHello world');
    });

    test('strips leading newline after <think> when split across chunks', () async {
      final sseLines = [
        'data: ${jsonEncode({
          'id': 'chatcmpl-c1',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'qwen',
          'choices': [
            {
              'index': 0,
              'delta': {'role': 'assistant', 'content': '<think>'},
              'finish_reason': null,
            }
          ],
        })}\n\n',
        'data: ${jsonEncode({
          'id': 'chatcmpl-c1',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'qwen',
          'choices': [
            {
              'index': 0,
              'delta': {'content': '\nThought line</think>Answer'},
              'finish_reason': 'stop',
            }
          ],
        })}\n\n',
        'data: [DONE]\n\n',
      ];

      final mock = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.fromIterable(sseLines.map(utf8.encode)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final model = OmlxChatModel(
        name: 'qwen',
        enableThinking: true,
        httpClient: mock,
      );

      final results = await model.sendStream([
        ChatMessage.user('Question'),
      ]).toList();

      final thinkingParts = results
          .expand((r) => r.output.parts)
          .whereType<ThinkingPart>()
          .toList();
      final textParts = results
          .expand((r) => r.output.parts)
          .whereType<TextPart>()
          .toList();

      expect(thinkingParts.length, 1);
      expect(thinkingParts.first.text, 'Thought line');

      expect(textParts.length, 1);
      expect(textParts.first.text, 'Answer');
    });

    test('strips trailing newline before </think> when split across chunks', () async {
      final sseLines = [
        'data: ${jsonEncode({
          'id': 'chatcmpl-c2',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'qwen',
          'choices': [
            {
              'index': 0,
              'delta': {'role': 'assistant', 'content': '<think>Thought line\n'},
              'finish_reason': null,
            }
          ],
        })}\n\n',
        'data: ${jsonEncode({
          'id': 'chatcmpl-c2',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'qwen',
          'choices': [
            {
              'index': 0,
              'delta': {'content': '</think>Answer'},
              'finish_reason': 'stop',
            }
          ],
        })}\n\n',
        'data: [DONE]\n\n',
      ];

      final mock = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.fromIterable(sseLines.map(utf8.encode)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final model = OmlxChatModel(
        name: 'qwen',
        enableThinking: true,
        httpClient: mock,
      );

      final results = await model.sendStream([
        ChatMessage.user('Question'),
      ]).toList();

      final thinkingParts = results
          .expand((r) => r.output.parts)
          .whereType<ThinkingPart>()
          .toList();
      final textParts = results
          .expand((r) => r.output.parts)
          .whereType<TextPart>()
          .toList();

      expect(thinkingParts.length, 1);
      expect(thinkingParts.first.text, 'Thought line');

      expect(textParts.length, 1);
      expect(textParts.first.text, 'Answer');
    });

    test('strips leading newlines after </think> when split across chunks', () async {
      final sseLines = [
        'data: ${jsonEncode({
          'id': 'chatcmpl-c3',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'qwen',
          'choices': [
            {
              'index': 0,
              'delta': {'role': 'assistant', 'content': '<think>Thought</think>'},
              'finish_reason': null,
            }
          ],
        })}\n\n',
        'data: ${jsonEncode({
          'id': 'chatcmpl-c3',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'qwen',
          'choices': [
            {
              'index': 0,
              'delta': {'content': '\n\nAnswer line.'},
              'finish_reason': 'stop',
            }
          ],
        })}\n\n',
        'data: [DONE]\n\n',
      ];

      final mock = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.fromIterable(sseLines.map(utf8.encode)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final model = OmlxChatModel(
        name: 'qwen',
        enableThinking: true,
        httpClient: mock,
      );

      final results = await model.sendStream([
        ChatMessage.user('Question'),
      ]).toList();

      final thinkingParts = results
          .expand((r) => r.output.parts)
          .whereType<ThinkingPart>()
          .toList();
      final textParts = results
          .expand((r) => r.output.parts)
          .whereType<TextPart>()
          .toList();

      expect(thinkingParts.length, 1);
      expect(thinkingParts.first.text, 'Thought');

      expect(textParts.length, 1);
      expect(textParts.first.text, 'Answer line.');
    });

    test('strips leading newlines after </think> when split as single newlines across chunks', () async {
      final sseLines = [
        'data: ${jsonEncode({
          'id': 'chatcmpl-c4',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'qwen',
          'choices': [
            {
              'index': 0,
              'delta': {'role': 'assistant', 'content': '<think>Thought</think>\n'},
              'finish_reason': null,
            }
          ],
        })}\n\n',
        'data: ${jsonEncode({
          'id': 'chatcmpl-c4',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'qwen',
          'choices': [
            {
              'index': 0,
              'delta': {'content': '\nAnswer line.'},
              'finish_reason': 'stop',
            }
          ],
        })}\n\n',
        'data: [DONE]\n\n',
      ];

      final mock = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.fromIterable(sseLines.map(utf8.encode)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final model = OmlxChatModel(
        name: 'qwen',
        enableThinking: true,
        httpClient: mock,
      );

      final results = await model.sendStream([
        ChatMessage.user('Question'),
      ]).toList();

      final thinkingParts = results
          .expand((r) => r.output.parts)
          .whereType<ThinkingPart>()
          .toList();
      final textParts = results
          .expand((r) => r.output.parts)
          .whereType<TextPart>()
          .toList();

      expect(thinkingParts.length, 1);
      expect(thinkingParts.first.text, 'Thought');

      expect(textParts.length, 1);
      expect(textParts.first.text, 'Answer line.');
    });

    test('treats <think> mid-response after user text as literal text even without server reasoning_content', () async {
      final sseLines = [
        'data: ${jsonEncode({
          'id': 'chatcmpl-mid',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'qwen',
          'choices': [
            {
              'index': 0,
              'delta': {'role': 'assistant', 'content': 'Here is an XML example:\n```xml\n<think>value</think>\n```'},
              'finish_reason': 'stop',
            }
          ],
        })}\n\n',
        'data: [DONE]\n\n',
      ];

      final mock = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.fromIterable(sseLines.map(utf8.encode)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final model = OmlxChatModel(
        name: 'qwen',
        enableThinking: false,
        httpClient: mock,
      );

      final results = await model.sendStream([
        ChatMessage.user('Question'),
      ]).toList();

      final thinkingParts = results
          .expand((r) => r.output.parts)
          .whereType<ThinkingPart>()
          .toList();
      final textParts = results
          .expand((r) => r.output.parts)
          .whereType<TextPart>()
          .toList();

      expect(thinkingParts, isEmpty);
      expect(textParts.length, 1);
      expect(textParts.first.text, contains('<think>value</think>'));
    });

    test('treats <think> in delta.content as literal text when server sends reasoning_content', () async {
      final sseLines = [
        'data: ${jsonEncode({
          'id': 'chatcmpl-think',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'deepseek-r1',
          'choices': [
            {
              'index': 0,
              'delta': {
                'role': 'assistant',
                'reasoning_content': 'Backend extracted thinking',
              },
              'finish_reason': null,
            }
          ],
        })}\n\n',
        'data: ${jsonEncode({
          'id': 'chatcmpl-think',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'deepseek-r1',
          'choices': [
            {
              'index': 0,
              'delta': {
                'content': 'Here is code: <think>tag inside code</think>',
              },
              'finish_reason': 'stop',
            }
          ],
        })}\n\n',
        'data: [DONE]\n\n',
      ];

      final mock = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.fromIterable(sseLines.map(utf8.encode)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final model = OmlxChatModel(
        name: 'deepseek-r1',
        enableThinking: true,
        httpClient: mock,
      );

      final results = await model.sendStream([
        ChatMessage.user('Question'),
      ]).toList();

      final thinkingParts = results
          .expand((r) => r.output.parts)
          .whereType<ThinkingPart>()
          .toList();
      final textParts = results
          .expand((r) => r.output.parts)
          .whereType<TextPart>()
          .toList();

      expect(thinkingParts.length, 1);
      expect(thinkingParts.first.text, 'Backend extracted thinking');

      expect(textParts.length, 1);
      expect(textParts.first.text, 'Here is code: <think>tag inside code</think>');
    });

    test('flushes tagBuffer when switching to fast path upon receiving server reasoning_content', () async {
      final sseLines = [
        'data: ${jsonEncode({
          'id': 'chatcmpl-flush',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'deepseek-r1',
          'choices': [
            {
              'index': 0,
              'delta': {
                'role': 'assistant',
                'content': '<th',
              },
              'finish_reason': null,
            }
          ],
        })}\n\n',
        'data: ${jsonEncode({
          'id': 'chatcmpl-flush',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'deepseek-r1',
          'choices': [
            {
              'index': 0,
              'delta': {
                'reasoning_content': 'Backend reasoning',
                'content': 'ink tag inside content',
              },
              'finish_reason': 'stop',
            }
          ],
        })}\n\n',
        'data: [DONE]\n\n',
      ];

      final mock = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.fromIterable(sseLines.map(utf8.encode)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final model = OmlxChatModel(
        name: 'deepseek-r1',
        enableThinking: true,
        httpClient: mock,
      );

      final results = await model.sendStream([
        ChatMessage.user('Question'),
      ]).toList();

      final thinkingParts = results
          .expand((r) => r.output.parts)
          .whereType<ThinkingPart>()
          .toList();
      final textParts = results
          .expand((r) => r.output.parts)
          .whereType<TextPart>()
          .toList();

      expect(thinkingParts.length, 1);
      expect(thinkingParts.first.text, 'Backend reasoning');

      // The buffered '<th' from chunk 1 should be prepended to chunk 2's content
      // resulting in '<think tag inside content', NOT emitted out of order at the end
      expect(textParts.length, 1);
      expect(textParts.first.text, '<think tag inside content');
    });

    test('accumulates tool call deltas across streaming chunks', () async {
      final sseLines = [
        'data: ${jsonEncode({
          'id': 'chatcmpl-tool',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'qwen',
          'choices': [
            {
              'index': 0,
              'delta': {
                'role': 'assistant',
                'tool_calls': [
                  {
                    'id': 'call_weather_1',
                    'index': 0,
                    'type': 'function',
                    'function': {'name': 'get_weather', 'arguments': '{"loc'},
                  }
                ],
              },
              'finish_reason': null,
            }
          ],
        })}\n\n',
        'data: ${jsonEncode({
          'id': 'chatcmpl-tool',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'qwen',
          'choices': [
            {
              'index': 0,
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'function': {'arguments': 'ation":"Paris"}'},
                  }
                ],
              },
              'finish_reason': 'tool_calls',
            }
          ],
        })}\n\n',
        'data: [DONE]\n\n',
      ];

      final mock = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.fromIterable(sseLines.map(utf8.encode)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final model = OmlxChatModel(
        name: 'qwen',
        tools: [
          Tool<Map<String, dynamic>>(
            name: 'get_weather',
            description: 'Gets weather',
            onCall: (args) => 'Sunny',
          ),
        ],
        httpClient: mock,
      );

      final results = await model.sendStream([
        ChatMessage.user('Weather in Paris?'),
      ]).toList();

      // Final chunk should emit the complete ToolPart.call
      expect(results.length, 1);
      final finalMessage = results.first.output;
      expect(finalMessage.toolCalls.length, 1);
      final toolCall = finalMessage.toolCalls.first;
      expect(toolCall.callId, 'call_weather_1');
      expect(toolCall.toolName, 'get_weather');
      expect(toolCall.arguments, {'location': 'Paris'});
      expect(results.first.finishReason, FinishReason.toolCalls);
    });

    test('runs with Agent orchestrator end-to-end', () async {
      final sseLines = [
        'data: ${jsonEncode({
          'id': 'chatcmpl-agent',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'qwen',
          'choices': [
            {
              'index': 0,
              'delta': {'role': 'assistant', 'content': 'Agent response!'},
              'finish_reason': 'stop',
            }
          ],
          'usage': {
            'prompt_tokens': 5,
            'completion_tokens': 3,
            'total_tokens': 8,
          },
        })}\n\n',
        'data: [DONE]\n\n',
      ];

      final mock = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.fromIterable(sseLines.map(utf8.encode)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final provider = OmlxProvider(httpClient: mock);
      final agent = Agent.forProvider(provider);

      final response = await agent.send('Test prompt');
      expect(response.output, 'Agent response!');
      expect(response.finishReason, FinishReason.stop);
    });

    test('never emits multiple TextParts in a single ChatMessage when chunk ends with tag prefix', () async {
      final sseLines = [
        'data: ${jsonEncode({
          'id': 'chatcmpl-prefix',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'qwen',
          'choices': [
            {
              'index': 0,
              'delta': {'role': 'assistant', 'content': 'Hello <th'},
              'finish_reason': null,
            }
          ],
        })}\n\n',
        'data: ${jsonEncode({
          'id': 'chatcmpl-prefix',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'qwen',
          'choices': [
            {
              'index': 0,
              'delta': {'content': 'ink> still text</think> done.'},
              'finish_reason': 'stop',
            }
          ],
        })}\n\n',
        'data: [DONE]\n\n',
      ];

      final mock = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.fromIterable(sseLines.map(utf8.encode)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final model = OmlxChatModel(
        name: 'qwen',
        httpClient: mock,
      );

      final results = await model.sendStream([
        ChatMessage.user('Hi'),
      ]).toList();

      for (final result in results) {
        final textPartCount = result.output.parts.whereType<TextPart>().length;
        expect(textPartCount, lessThanOrEqualTo(1));
      }

      // Also ensure Agent orchestrator runs without AssertionError
      final provider = OmlxProvider(httpClient: mock);
      final agent = Agent.forProvider(provider);
      final agentResult = await agent.send('Hi');
      expect(agentResult.output, contains('Hello <think> still text</think> done.'));
    });

    test('per-call options.temperature overrides model.temperature', () async {
      final sseLines = [
        'data: ${jsonEncode({
          'id': 'chatcmpl-temp',
          'object': 'chat.completion.chunk',
          'created': 1700000000,
          'model': 'qwen',
          'choices': [
            {
              'index': 0,
              'delta': {'content': 'ok'},
              'finish_reason': 'stop',
            }
          ],
        })}\n\n',
        'data: [DONE]\n\n',
      ];

      Map<String, dynamic>? capturedBody;
      final mock = MockClient.streaming((request, bodyStream) async {
        final bodyStr = await bodyStream.bytesToString();
        capturedBody = jsonDecode(bodyStr) as Map<String, dynamic>;
        return http.StreamedResponse(
          Stream.fromIterable(sseLines.map(utf8.encode)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final model = OmlxChatModel(
        name: 'qwen',
        temperature: 0.7,
        httpClient: mock,
      );
      expect(model.temperature, 0.7);

      // 1. Without call options, model.temperature (0.7) is used
      await model.sendStream([ChatMessage.user('Hi')]).drain<void>();
      expect(capturedBody?['temperature'], 0.7);

      // 2. With per-call options.temperature (0.2), it overrides model.temperature (0.7)
      await model.sendStream(
        [ChatMessage.user('Hi')],
        options: const OmlxChatOptions(temperature: 0.2),
      ).drain<void>();
      expect(capturedBody?['temperature'], 0.2);

      // 3. Model initialized via defaultOptions picks up temperature
      final modelWithOptions = OmlxChatModel(
        name: 'qwen',
        defaultOptions: const OmlxChatOptions(temperature: 0.4),
        httpClient: mock,
      );
      expect(modelWithOptions.temperature, 0.4);

      await modelWithOptions.sendStream([ChatMessage.user('Hi')]).drain<void>();
      expect(capturedBody?['temperature'], 0.4);
    });
  });
}
