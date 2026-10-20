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
              'delta': {},
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
  });
}
