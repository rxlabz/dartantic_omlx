/// A dartantic_ai provider for oMLX, the OpenAI-compatible LLM inference server
/// for Apple Silicon.
library;

export 'package:dartantic_ai/dartantic_ai.dart';
export 'package:domlx/domlx.dart'
    show
        AudioSpeechRequest,
        AudioTranscriptionRequest,
        AudioTranscriptionResponse,
        HealthResponse,
        ModelStatus,
        RerankRequest,
        RerankResponse,
        RerankResult,
        UnloadModelResponse;

export 'src/chat_models/omlx_chat.dart';
export 'src/embeddings_models/omlx_embeddings.dart';
export 'src/media_gen_models/omlx_media_gen.dart';
export 'src/providers/omlx_provider.dart';
