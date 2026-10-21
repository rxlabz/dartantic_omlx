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
            ThinkingPart('I should check the weather in Paris first.'),
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
      expect(
        omlxMessages.first.reasoningContent,
        'I should check the weather in Paris first.',
      );
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
      final rawSchema = schemaMap?['schema'] as Map<String, dynamic>;
      expect(rawSchema['additionalProperties'], false);
      expect(rawSchema['required'], contains('fruits'));
    });

    test('buildChatCompletionRequest deep-merges chat_template_kwargs and sets explicit enable_thinking', () {
      // 1. When enableThinking is false, explicit enable_thinking: false is sent
      final req1 = buildChatCompletionRequest(
        [ChatMessage.user('Hi')],
        modelName: 'test-model',
        options: const OmlxChatOptions(),
        enableThinking: false,
      );
      expect(
        req1.extra['chat_template_kwargs'],
        {'enable_thinking': false},
      );

      // 2. When enableThinking is true and options has custom kwargs, they are deep-merged
      final req2 = buildChatCompletionRequest(
        [ChatMessage.user('Hi')],
        modelName: 'test-model',
        options: const OmlxChatOptions(
          chatTemplateKwargs: {'custom_param': 123},
          extra: {
            'chat_template_kwargs': {'nested': true},
            'other_param': 'test',
          },
        ),
        enableThinking: true,
      );
      expect(
        req2.extra['chat_template_kwargs'],
        {
          'enable_thinking': true,
          'custom_param': 123,
          'nested': true,
        },
      );
      expect(req2.extra['other_param'], 'test');
    });

    test('prepareSchemaForOmlx recursively adds additionalProperties: false and ensures properties', () {
      final inputSchema = {
        'type': 'object',
        'format': 'date-time', // should be stripped
        'properties': {
          'user': {
            'type': 'object',
            'properties': {
              'age': {'type': 'integer'},
            },
          },
          'tags': {
            'type': 'array',
            'items': {
              'type': 'object',
            },
          },
          'nullableField': {
            'type': ['string', 'null'],
          },
        },
      };

      final normalized = prepareSchemaForOmlx(inputSchema, strict: true);

      expect(normalized.containsKey('format'), isFalse);
      expect(normalized['additionalProperties'], false);
      expect(normalized['required'], containsAll(['user', 'tags', 'nullableField']));

      final userObj = (normalized['properties'] as Map<String, dynamic>)['user'] as Map<String, dynamic>;
      expect(userObj['additionalProperties'], false);
      expect(userObj['required'], ['age']);

      final tagsItems = ((normalized['properties'] as Map<String, dynamic>)['tags'] as Map<String, dynamic>)['items'] as Map<String, dynamic>;
      expect(tagsItems['additionalProperties'], false);
      expect(tagsItems['properties'], isA<Map>());

      final nullableField = (normalized['properties'] as Map<String, dynamic>)['nullableField'] as Map<String, dynamic>;
      expect(nullableField['type'], containsAll(['string', 'null']));

      // In non-strict mode (tool parameters), nullable types are flattened to string
      final toolSchema = prepareSchemaForOmlx(inputSchema, strict: false);
      final toolNullableField = (toolSchema['properties'] as Map<String, dynamic>)['nullableField'] as Map<String, dynamic>;
      expect(toolNullableField['type'], 'string');
    });

    test('prepareSchemaForOmlx recursively normalizes anyOf, oneOf, and allOf', () {
      final inputSchema = {
        'anyOf': [
          {
            'type': 'object',
            'properties': {'kind': {'type': 'string'}},
          },
          {
            'type': 'object',
            // Missing properties map
          },
        ],
        'oneOf': [
          {
            'type': 'object',
            'properties': {'val': {'type': 'number'}},
          },
        ],
        'allOf': [
          {
            'type': 'object',
            'format': 'custom',
          },
        ],
      };

      final normalized = prepareSchemaForOmlx(inputSchema, strict: true);

      final anyOfList = normalized['anyOf'] as List;
      expect(anyOfList.length, 2);
      expect((anyOfList[0] as Map)['additionalProperties'], false);
      expect((anyOfList[0] as Map)['required'], ['kind']);
      expect((anyOfList[1] as Map)['additionalProperties'], false);
      expect((anyOfList[1] as Map)['properties'], isA<Map>());

      final oneOfList = normalized['oneOf'] as List;
      expect((oneOfList[0] as Map)['additionalProperties'], false);
      expect((oneOfList[0] as Map)['required'], ['val']);

      final allOfList = normalized['allOf'] as List;
      expect((allOfList[0] as Map).containsKey('format'), isFalse);
      expect((allOfList[0] as Map)['additionalProperties'], false);
      expect((allOfList[0] as Map)['properties'], isA<Map>());
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

    test('toOmlxMessages omits reasoningContent on past completed turns but keeps on recent/tool-calling messages', () {
      final messages = [
        ChatMessage.user('First turn'),
        ChatMessage(
          role: ChatMessageRole.model,
          parts: const [
            ThinkingPart('Historical thinking that should not be re-sent'),
            TextPart('First answer'),
          ],
        ),
        ChatMessage.user('Second turn'),
        ChatMessage(
          role: ChatMessageRole.model,
          parts: const [
            ThinkingPart('Thinking for tool call'),
            ToolPart.call(callId: 'call_1', toolName: 'test', arguments: {}),
          ],
        ),
        ChatMessage(
          role: ChatMessageRole.user,
          parts: const [
            ToolPart.result(callId: 'call_1', toolName: 'test', result: 'ok'),
          ],
        ),
        ChatMessage(
          role: ChatMessageRole.model,
          parts: const [
            ThinkingPart('Most recent thinking'),
            TextPart('Final answer'),
          ],
        ),
      ];

      final omlxMessages = messages.toOmlxMessages();

      // First model message (index 1 in omlxMessages): completed turn, reasoning omitted
      expect(omlxMessages[1].reasoningContent, isNull);
      expect(omlxMessages[1].textContent, 'First answer');

      // Second model message (index 3 in omlxMessages): has tool calls, reasoning preserved
      expect(omlxMessages[3].reasoningContent, 'Thinking for tool call');
      expect(omlxMessages[3].toolCalls?.length, 1);

      // Third model message (index 5 in omlxMessages): most recent message, reasoning preserved
      expect(omlxMessages[5].reasoningContent, 'Most recent thinking');
      expect(omlxMessages[5].textContent, 'Final answer');
    });

    test('chatMessageFromOmlx parses inline <think> tag when reasoningContent is null', () {
      const omlxMsg = o.ChatMessage(
        role: 'assistant',
        content: '<think>\nInline thought\n</think>\nActual response',
      );

      final msg = chatMessageFromOmlx(omlxMsg);
      expect(msg.role, ChatMessageRole.model);

      final thinking = msg.parts.whereType<ThinkingPart>().toList();
      final text = msg.parts.whereType<TextPart>().toList();

      expect(thinking.length, 1);
      expect(thinking.first.text, 'Inline thought');

      expect(text.length, 1);
      expect(text.first.text, 'Actual response');
    });
  });
}
