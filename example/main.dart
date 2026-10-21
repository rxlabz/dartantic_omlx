// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dartantic_omlx/dartantic_omlx.dart';

// ignore: non_constant_identifier_names
final OMLX_API_KEY = String.fromEnvironment('OMLX_API_KEY');

void main() async {
  // 1. Register the oMLX provider globally with dartantic_ai
  final provider = OmlxProvider(apiKey: OMLX_API_KEY);
  OmlxProvider.register(() => provider);

  print('=== 1. Discover Available Local Models ===');
  final models = await provider.listModels().toList();
  for (final model in models) {
    print(' - ${model.name} (${model.kinds.map((k) => k.name).join(', ')})');
  }

  final chatModel = models
      .where((m) => m.kinds.contains(ModelKind.chat))
      .firstOrNull;
  final embeddingsModel = models
      .where((m) => m.kinds.contains(ModelKind.embeddings))
      .firstOrNull;
  final ttsModel = models
      .where(
        (m) =>
            m.kinds.contains(ModelKind.tts) ||
            m.kinds.contains(ModelKind.media),
      )
      .firstOrNull;
  final rerankModel = models
      .where(
        (m) =>
            m.kinds.contains(ModelKind.other) ||
            m.name.toLowerCase().contains('rerank'),
      )
      .firstOrNull;

  if (chatModel == null) {
    print('\nNo local chat model found for chat/tool/structured-output demos.');
  } else {
    print('\nUsing chat model: ${chatModel.name}');

    // 2. Streaming Chat with Thinking / Reasoning
    print('\n=== 2. Agent Streaming Chat with oMLX ===');
    final chatAgent = Agent(
      'omlx:${chatModel.name}',
      temperature: 0.7,
      enableThinking: true,
      chatModelOptions: const OmlxChatOptions(extra: {'thinking_budget': 256}),
    );

    final stream = chatAgent.sendStream(
      'Why is unified memory on Apple Silicon advantageous for local LLMs? '
      'Explain in 2 sentences.',
    );

    await for (final result in stream) {
      if (result.thinking != null) {
        stdout.write(result.thinking);
      }
      if (result.output.isNotEmpty) {
        stdout.write(result.output);
      }
    }
    stdout.writeln();

    // 3. Tool Calling
    print('\n=== 3. Tool Calling ===');
    final weatherTool = Tool<Map<String, dynamic>>(
      name: 'get_current_weather',
      description: 'Get the current weather for a given city',
      inputSchema: Schema.fromMap({
        'type': 'object',
        'properties': {
          'city': {
            'type': 'string',
            'description': 'The city name (e.g., Tokyo, Paris)',
          },
        },
        'required': ['city'],
      }),
      onCall: (args) async {
        final city = args['city'] as String? ?? 'Unknown';
        print(' -> [Tool invoked] get_current_weather(city: $city)');
        return {'city': city, 'temperature_c': 22, 'condition': 'Sunny'};
      },
    );

    final toolAgent = Agent('omlx:${chatModel.name}', tools: [weatherTool]);

    final toolResponse = await toolAgent.send(
      'What is the weather like in Tokyo right now?',
    );
    print('Agent: ${toolResponse.output}');

    // 4. Structured Output (JSON Schema)
    print('\n=== 4. Structured Output ===');
    final hardwareSchema = Schema.fromMap({
      'type': 'object',
      'properties': {
        'chip': {'type': 'string'},
        'unified_memory_gb': {'type': 'integer'},
        'advantages': {
          'type': 'array',
          'items': {'type': 'string'},
        },
      },
      'required': ['chip', 'unified_memory_gb', 'advantages'],
    });

    final structuredResult = await chatAgent.sendFor<Map<String, dynamic>>(
      'Provide a spec summary for an Apple M4 Max with 128GB unified memory '
      'running local MLX models.',
      outputSchema: hardwareSchema,
    );

    final spec = structuredResult.output;
    print('Chip: ${spec['chip']}');
    print('Unified Memory: ${spec['unified_memory_gb']} GB');
    print('Advantages: ${(spec['advantages'] as List<dynamic>).join(', ')}');
  }

  // 5. Embeddings
  print('\n=== 5. Embeddings ===');
  if (embeddingsModel == null) {
    print('No local embeddings model found.');
  } else {
    print('Using embeddings model: ${embeddingsModel.name}');
    final embeddings = provider.createEmbeddingsModel(
      name: embeddingsModel.name,
    );
    final vectorResult = await embeddings.embedQuery(
      'Apple Silicon Unified Memory',
    );
    print(
      'Generated embedding vector: ${vectorResult.output.length} dimensions',
    );
    embeddings.dispose();
  }

  // 6. Text-to-Speech (TTS Media Generation)
  print('\n=== 6. Text-to-Speech (TTS) ===');
  if (ttsModel == null) {
    print('No local TTS model found.');
  } else {
    print('Using TTS model: ${ttsModel.name}');
    final mediaModel = provider.createMediaModel(
      name: ttsModel.name,
      options: const OmlxMediaGenerationModelOptions(
        voice: 'af_heart',
        responseFormat: 'wav',
      ),
    );

    final mediaStream = mediaModel.generateMediaStream(
      'Hello from local oMLX inference on Apple Silicon!',
      mimeTypes: const ['audio/wav'],
    );

    await for (final chunk in mediaStream) {
      for (final asset in chunk.assets) {
        if (asset is DataPart) {
          print(
            'Synthesized audio: ${asset.name} '
            '(${asset.bytes.length} bytes, ${asset.mimeType})',
          );
        }
      }
    }
    mediaModel.dispose();
  }

  // 7. Semantic Reranking
  print('\n=== 7. Semantic Document Reranking ===');
  if (rerankModel == null) {
    print('No local reranker model found.');
  } else {
    print('Using rerank model: ${rerankModel.name}');
    final rankings = await provider.rerank(
      model: rerankModel.name,
      query: 'How does KV prefix caching speed up local LLM inference?',
      documents: const [
        'Photosynthesis converts light energy into chemical energy in plants.',
        'SSD prefix caching stores evaluated KV cache blocks to skip redundant prompt prefill.',
        'Continuous batching dynamically schedules sequences to maximize GPU utilization.',
      ],
      topN: 2,
    );

    for (final item in rankings) {
      print(
        ' - [Score: ${item.relevanceScore.toStringAsFixed(4)}] '
        '(Doc #${item.index}): ${item.document}',
      );
    }
  }
}
