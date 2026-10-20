import 'dart:convert';
import 'dart:typed_data';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:dartantic_omlx/src/chat_models/omlx_chat_options.dart';
import 'package:dartantic_omlx/src/chat_models/omlx_message_mappers.dart';
import 'package:domlx/domlx.dart' as o;
import 'package:test/test.dart';

void main() {
  group('OmlxMessageMappers', () {
    test('converts system message', () {
      final messages = [
        ChatMessage.system('You are a helpful assistant.'),
      ];
      final omlxMessages = messages.toOmlxMessages();
      expect(omlxMessages.length, 1);
      expect(omlxMessages.first.role, 'system');
      expect(omlxMessages.first.textContent, 'You are a helpful assistant.');
    });

    test('converts plain user message', () {
      final messages = [
        ChatMessage.user('Hello oMLX!'),
      ];
      final omlxMessages = messages.toOmlxMessages();
      expect(omlxMessages.length, 1);
      expect(omlxMessages.first.role, 'user');
      expect(omlxMessages.first.textContent, 'Hello oMLX!');
    });

    test('converts multimodal user message with image DataPart', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final messages = [
        ChatMessage.user(
          'What is in this picture?',
          parts: [DataPart(bytes, mimeType: 'image/png')],
        ),
      ];
      final omlxMessages = messages.toOmlxMessages();
      expect(omlxMessages.length, 1);
      expect(omlxMessages.first.role, 'user');
      final content = omlxMessages.first.content;
      expect(content, isA<List>());
      final parts = content as List;
      expect(parts.length, 2);
      expect(parts[0], isA<o.TextContentPart>());
      expect(parts[1], isA<o.ImageContentPart>());
      final img = parts[1] as o.ImageContentPart;
      expect(img.url, startsWith('data:image/png;base64,'));
    });

    test('converts multimodal user message with LinkPart', () {
      final messages = [
        ChatMessage.user(
          'Check this link',
          parts: [
            LinkPart(
              Uri.parse('https://example.com/photo.jpg'),
              mimeType: 'image/jpeg',
            ),
          ],
        ),
      ];
      final omlxMessages = messages.toOmlxMessages();
      expect(omlxMessages.length, 1);
      final parts = omlxMessages.first.content as List;
      expect(parts.length, 2);
      expect(parts[1], isA<o.ImageContentPart>());
      expect(
        (parts[1] as o.ImageContentPart).url,
        'https://example.com/photo.jpg',
      );
    });

    test('expands multiple tool results into separate tool messages', () {
      final messages = [
        ChatMessage(
          role: ChatMessageRole.user,
          parts: const [
            ToolPart.result(
              callId: 'call_1',
              toolName: 'get_weather',
              result: {'temp': 22},
            ),
            ToolPart.result(
              callId: 'call_2',
              toolName: 'get_time',
              result: '12:00 PM',
            ),
          ],
        ),
      ];
      final omlxMessages = messages.toOmlxMessages();
      expect(omlxMessages.length, 2);
      expect(omlxMessages[0].role, 'tool');
      expect(omlxMessages[0].toolCallId, 'call_1');
      expect(omlxMessages[0].textContent, jsonEncode({'temp': 22}));
      expect(omlxMessages[1].role, 'tool');
      expect(omlxMessages[1].toolCallId, 'call_2');
      expect(omlxMessages[1].textContent, '12:00 PM');
    });

    test('converts model message with text and tool calls', () {
      final messages = [
        ChatMessage(
          role: ChatMessageRole.model,
          parts: const [
            TextPart('Checking weather...'),
            ToolPart.call(
              callId: 'call_1',
              toolName: 'get_weather',
              arguments: {'city': 'Paris'},
            ),
          ],
        ),
      ];
      final omlxMessages = messages.toOmlxMessages();
      expect(omlxMessages.length, 1);
      expect(omlxMessages.first.role, 'assistant');
      expect(omlxMessages.first.textContent, 'Checking weather...');
      expect(omlxMessages.first.toolCalls?.length, 1);
      expect(omlxMessages.first.toolCalls?.first.id, 'call_1');
      expect(
        omlxMessages.first.toolCalls?.first.function.name,
        'get_weather',
      );
    });

    test('converts dartantic Tools to oMLX Tools', () {
      final tools = [
        Tool<Map<String, dynamic>>(
          name: 'get_weather',
          description: 'Gets current weather',
          inputSchema: S.object(
            properties: {'location': S.string(description: 'City name')},
            required: ['location'],
          ),
          onCall: (args) => 'Sunny',
        ),
      ];
      final omlxTools = tools.toOmlxTools();
      expect(omlxTools.length, 1);
      expect(omlxTools.first.function.name, 'get_weather');
      expect(omlxTools.first.function.description, 'Gets current weather');
      expect(
        omlxTools.first.function.parameters?['properties'],
        isNotNull,
      );
    });

    test('buildChatCompletionRequest with structured output schema', () {
      final req = buildChatCompletionRequest(
        [ChatMessage.user('List 3 fruits')],
        modelName: 'test-model',
        options: const OmlxChatOptions(),
        outputSchema: S.object(
          properties: {
            'fruits': S.list(items: S.string()),
          },
          required: ['fruits'],
        ),
      );
      expect(req.model, 'test-model');
      expect(req.responseFormat?.type, 'json_schema');
      final schemaMap = req.responseFormat?.jsonSchema;
      expect(schemaMap?['name'], 'output_schema');
      expect(schemaMap?['strict'], true);
    });

    test('OmlxToolCallAccumulator merges split delta chunks', () {
      final accumulator = OmlxToolCallAccumulator();
      accumulator.addAll([
        const o.ToolCall(
          id: 'call_abc',
          index: 0,
          function: o.FunctionCall(name: 'calculator', arguments: '{"op":'),
        ),
      ]);
      accumulator.addAll([
        const o.ToolCall(
          index: 0,
          function: o.FunctionCall(arguments: '"add","a":1,"b":2}'),
        ),
      ]);

      final toolCalls = accumulator.build();
      expect(toolCalls.length, 1);
      expect(toolCalls.first.callId, 'call_abc');
      expect(toolCalls.first.toolName, 'calculator');
      expect(toolCalls.first.arguments, {'op': 'add', 'a': 1, 'b': 2});
    });
  });
}
