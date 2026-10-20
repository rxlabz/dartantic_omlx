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

  print('\n=== 2. Agent Streaming Chat with oMLX ===');
  if (chatModel == null) {
    print('No local chat model found.');
  } else {
    print('Using chat model: ${chatModel.name}\n');
    final agent = Agent(
      'omlx:${chatModel.name}',
      temperature: 0.7,
      enableThinking: true,
    );

    final stream = agent.sendStream(
      'Why is unified memory on Apple Silicon advantageous for local LLMs? Explain in 2 sentences.',
    );

    await for (final result in stream) {
      if (result.thinking != null) {
        print('[Thinking]: ${result.thinking}');
      }
      if (result.output.isNotEmpty) {
        print(result.output);
      }
    }
  }

  print('\n=== 3. Embeddings ===');
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
}
