## 1.0.0+1

- Update README.md

## 1.0.0

- Initial release:
- **`OmlxProvider`**: Global `Agent` registration (`omlx` and `mlx` aliases), automatic model capability discovery (`listModels`), and environment/base URL configuration.
- **`OmlxChatModel`**:
  - Streaming and non-streaming chat generation (`sendStream`).
  - Reasoning / thinking model support with transparent extraction of server `reasoning_content` and inline `<think>...</think>` blocks into `ThinkingPart`s.
  - Multi-turn function and tool calling with streaming argument accumulation.
  - Native structured output via `ResponseFormat.jsonSchema` and recursive JSON schema normalization (`prepareSchemaForOmlx`).
  - Prefix cache and timing metrics (`cached_tokens`, `prefill_duration`, `generation_duration`) surfaced in response metadata and usage statistics.
- **`OmlxEmbeddingsModel`**: Text embedding generation (`embedQuery`, `embedDocuments`) with batch chunking, index ordering, and float/base64 decoding.
- **`OmlxMediaGenerationModel`**: Text-to-Speech (TTS) audio synthesis via `generateMediaStream` with support for `mp3`, `wav`, `opus`, `aac`, `flac`, and `pcm` formats.
- **oMLX Server Extensions**: Direct provider helpers for `/health` (`health`), model memory inspection (`modelsStatus`), memory reclamation (`unloadModel`), semantic document reranking (`rerank`), and audio transcription (`transcribeAudio` / `transcribeAudioBytes`).

