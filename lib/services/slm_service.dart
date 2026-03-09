import 'dart:io';
import 'dart:async';
import 'dart:ffi';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/constants.dart';

abstract class SlmService {
  Future<void> initialize();
  Future<String> generateResponse(String prompt, {int timeoutSeconds = 120});
  void dispose();
}

class LocalSlmService implements SlmService {
  static final LocalSlmService _instance = LocalSlmService._internal();
  factory LocalSlmService() => _instance;
  LocalSlmService._internal();

  LlamaParent? _processor;
  bool _isInitializing = false;

  @override
  Future<void> initialize() async {
    if (_processor != null) return;

    if (_isInitializing) {
      while (_isInitializing) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (_processor != null) return;
    }

    _isInitializing = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelPath = '${dir.path}/${AppConstants.modelFileName}';
      final file = File(modelPath);

      if (!await file.exists()) {
        debugPrint('Copying model from assets to documents directory...');
        try {
          final byteData = await rootBundle.load(AppConstants.modelAssetPath);
          await file.writeAsBytes(byteData.buffer.asUint8List());
          debugPrint('Model copied successfully to $modelPath');
        } catch (e) {
          throw Exception('Failed to copy model from assets: $e');
        }
      } else {
        debugPrint('Model already exists at $modelPath');
      }

      if (Platform.isAndroid) {
        for (final lib in ['libomp.so', 'libggml-base.so', 'libggml-cpu.so', 'libggml.so']) {
          try {
            DynamicLibrary.open(lib);
            debugPrint('Loaded $lib in LocalSlmService');
          } catch (e) {
            debugPrint('Failed to preload $lib: $e');
          }
        }
      }

      Llama.libraryPath = 'libllama.so';

      final modelParams = ModelParams()
        ..nGpuLayers = 0
        ..mainGpu = -1
        ..splitMode = LlamaSplitMode.none
        ..useMemorymap = false
        ..checkTensors = false;

      final contextParams = ContextParams()
        ..nCtx = AppConstants.slmContextSize
        ..nBatch = AppConstants.slmBatchSize
        ..nUbatch = AppConstants.slmBatchSize
        ..nThreads = AppConstants.slmThreads
        ..nThreadsBatch = AppConstants.slmBatchSize;

      final loadCommand = LlamaLoad(
        path: modelPath,
        modelParams: modelParams,
        contextParams: contextParams,
        samplingParams: SamplerParams(),
      );

      _processor = LlamaParent(loadCommand);
      await _processor!.init();
      debugPrint('Llama initialized successfully in LocalSlmService');
    } catch (e) {
      debugPrint('ERROR: Llama engine failed to initialize: $e');
      _processor = null;
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  @override
  Future<String> generateResponse(String prompt, {int timeoutSeconds = 120}) async {
    await initialize();

    debugPrint('Sending prompt to LLM (${prompt.length} chars)...');
    final promptId = await _processor!.sendPrompt(prompt);
    final buffer = StringBuffer();

    final sub = _processor!.stream.listen((token) {
      if (token.contains('<|im_end|>') || 
         (token.length > 5 && token.trimRight().endsWith('```'))) {
        _processor!.stop();
      } else {
        buffer.write(token);
      }
    });

    try {
      debugPrint('Waiting for completion...');
      await _processor!.waitForCompletion(promptId).timeout(Duration(seconds: timeoutSeconds));
    } on TimeoutException {
      debugPrint('Completion timed out.');
      _processor!.stop();
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      debugPrint('Completion error in LocalSlmService: $e');
    } finally {
      await sub.cancel();
    }

    String response = buffer.toString().trim();
    return response.replaceAll('<|im_start|>', '').replaceAll('<|im_end|>', '').trim();
  }

  @override
  void dispose() {
    _processor?.dispose();
    _processor = null;
  }
}
