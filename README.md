# dartantic_omlx

A [Dartantic AI](https://github.com/csells/dartantic_ai) provider package for **[oMLX](https://github.com/jundot/omlx)** (macOS Apple Silicon LLM inference server with continuous batching and SSD prefix caching), built on top of [`domlx`](https://github.com/rxlabz/domlx).

---

## Features

- **Agent Integration**: Register `OmlxProvider` to use `Agent('omlx:model-name')` and `Agent('mlx:model-name')`.
- **Reasoning / Thinking Models**: Transparent extraction of `<think>` / `reasoning_content` deltas surfaced directly as `ThinkingPart`s and real-time `thinking` stream chunks.
- **Function / Tool Calling**: Multi-turn tool execution with streaming argument accumulation and automatic tool-call ID tracking.
- **Structured Output**: Native JSON schema enforcement via `ResponseFormat.jsonSchema` for typed responses.
- **Prefix Cache & Timings**: Token usage statistics augmented with oMLX metadata (`cached_tokens`, `prefill_duration`, `generation_duration`).
- **Text Embeddings**: Vector embedding generation (`embedQuery`, `embedDocuments`) with batch chunking.
- **Audio TTS (Media Generation)**: Synthesize speech via Kokoro/Whisper models directly through `createMediaModel`.
- **oMLX Server Extensions**: Access `/health`, `/v1/models/status`, `/v1/models/{id}/unload`, `/v1/rerank`, and `/v1/audio/transcriptions`.

---

## Getting Started

Add `dartantic_omlx` to your `pubspec.yaml`:

```yaml
dependencies:
  dartantic_omlx:
    path: /path/to/dartantic_omlx
```

---

## Usage

### 1. Global Registration with `Agent`

Register `OmlxProvider` once at application startup to enable standard Dartantic model strings:

```dart
import 'package:dartantic_omlx/dartantic_omlx.dart';

void main() async {
  // Register 'omlx' and 'mlx' provider aliases
  OmlxProvider.register();

  // Create an Agent with an oMLX model
  final agent = Agent(
    'omlx:mlx-community/Qwen2.5-7B-Instruct-4bit',
    temperature: 0.7,
    enableThinking: true,
  );

  final stream = agent.sendStream('Explain continuous batching in 2 sentences.');
  await for (final chunk in stream) {
    if (chunk.thinking != null) {
      print('[Thinking]: ${chunk.thinking}');
    }
    if (chunk.output.isNotEmpty) {
      print(chunk.output);
    }
  }
}
```

### 2. Tool Calling with Agent

```dart
final agent = Agent(
  'omlx:mlx-community/Qwen2.5-7B-Instruct-4bit',
  tools: [
    Tool<Map<String, dynamic>>(
      name: 'get_current_weather',
      description: 'Get the current weather in a city',
      inputSchema: S.object(
        properties: {'location': S.string(description: 'City name')},
        required: ['location'],
      ),
      onCall: (args) async => {'temperature': 21, 'condition': 'Sunny'},
    ),
  ],
);

final response = await agent.send('What is the weather in Tokyo?');
print(response.output);
```

### 3. Embeddings

```dart
final provider = OmlxProvider();
final embeddings = provider.createEmbeddingsModel(name: 'bge-micro');

final result = await embeddings.embedQuery('Apple Silicon Unified Memory');
print('Vector dimensions: ${result.output.length}');
```

### 4. Text-to-Speech (TTS Media Model)

```dart
final mediaModel = provider.createMediaModel(
  name: 'mlx-community/Kokoro-82M-bf16',
  options: const OmlxMediaGenerationModelOptions(voice: 'af_heart'),
);

final stream = mediaModel.generateMediaStream(
  'Hello from local inference on Mac!',
  mimeTypes: ['audio/mp3'],
);

await for (final chunk in stream) {
  for (final asset in chunk.assets) {
    if (asset is DataPart) {
      print('Synthesized ${asset.bytes.length} bytes of ${asset.mimeType}');
    }
  }
}
```

### 5. Server Lifecycle & Reranking

```dart
final provider = OmlxProvider(baseUrl: Uri.parse('http://localhost:8000'));

// Health check
final health = await provider.health();
print('Healthy: ${health.isHealthy}');

// Model memory status
final statuses = await provider.modelsStatus();
for (final status in statuses) {
  print('Model ${status.modelId} loaded: ${status.isLoaded}');
}

// Unload model to reclaim Unified Memory
await provider.unloadModel('mlx-community/Qwen2.5-7B-Instruct-4bit');

// Semantic reranking
final rankings = await provider.rerank(
  query: 'KV caching',
  documents: [
    'Prefix caching saves prompt evaluation time.',
    'Photosynthesis uses light energy.',
  ],
);
```

---

## License

MIT
