/// Central configuration constants for the SLM pipeline.
/// Change [modelFileName] here to swap the on-device model everywhere.
class AppConstants {
  // Model filename as bundled in assets/models/ and copied to app documents.
  // Must match the asset declared in pubspec.yaml.
  static const String modelFileName = 'smollm2-360m-instruct-q4_k_m.gguf';
  static const String modelAssetPath = 'assets/models/$modelFileName';

  // SLM runtime settings
  static const int slmContextSize = 2048;  // 360M can handle a larger context
  static const int slmBatchSize = 512;
  static const int slmThreads = 4;
  static const int slmTimeoutSeconds = 120;
}
