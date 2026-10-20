import 'package:dartantic_omlx/dartantic_omlx.dart';

void main() async {
  // 1. Register the oMLX provider globally with dartantic_ai
  OmlxProvider.register();

  print('=== 1. Agent Streaming Chat with oMLX ===');
  final agent = Agent(
    'omlx:mlx-community/Qwen2.5-7B-Instruct-4bit',
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

  print('\n=== 2. Direct Provider Extensions (Models & Embeddings) ===');
  final provider = OmlxProvider();

  // List discovered models
  print('\nAvailable models:');
  await for (final model in provider.listModels()) {
    print(' - ${model.name} (${model.kinds.map((k) => k.name).join(', ')})');
  }

  // Embeddings
  final embeddings = provider.createEmbeddingsModel(
    name: 'bge-micro',
  );
  final vectorResult = await embeddings.embedQuery('Apple Silicon Unified Memory');
  print('\nGenerated embedding vector: ${vectorResult.output.length} dimensions');
}
