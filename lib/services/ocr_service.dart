import 'dart:io';
import 'dart:ffi';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:path_provider/path_provider.dart';
import '../models/ocr_result.dart';

class OcrService {
  final TextRecognizer _textRecognizer =
  TextRecognizer(script: TextRecognitionScript.latin);
  LlamaParent? _processor;
  bool _isInitializing = false;

  Future<OcrResult> extractText(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final RecognizedText recognizedText =
      await _textRecognizer.processImage(inputImage);

      final extractedText = recognizedText.text;

      return OcrResult(
        text: extractedText.isEmpty ? "No text found in the image." : extractedText,
        confidence: 1.0,
      );
    } catch (e) {
      throw Exception('Failed to perform local OCR: $e');
    }
  }

  Future<void> _ensureEngineReady() async {
    if (_processor != null) return;

    // Prevent concurrent initialization attempts
    if (_isInitializing) {
      // Wait until initialization completes
      while (_isInitializing) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (_processor != null) return;
    }

    _isInitializing = true;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelPath =
          '${dir.path}/smollm2-135m-instruct-q4_k_m.gguf';
      final file = File(modelPath);

      // Copy model from assets if it doesn't exist locally
      if (!await file.exists()) {
        debugPrint('Copying model from assets to documents directory...');
        try {
          final byteData = await rootBundle.load('assets/models/smollm2-135m-instruct-q4_k_m.gguf');
          await file.writeAsBytes(byteData.buffer.asUint8List());
          debugPrint('Model copied successfully to $modelPath');
        } catch (e) {
          throw Exception("Failed to copy model from assets: $e");
        }
      } else {
        debugPrint('Model already exists at $modelPath');
      }

      debugPrint('Initializing llama_cpp_dart...');

      // Pre-load native libraries on Android in the correct dependency order
      if (Platform.isAndroid) {
        for (final lib in ['libggml-base.so', 'libggml-cpu.so', 'libggml.so']) {
          try {
            DynamicLibrary.open(lib);
            debugPrint('Loaded $lib');
          } catch (e) {
            debugPrint('Failed to preload $lib: $e');
          }
        }
      }

      Llama.libraryPath = 'libllama.so';

      // KEY FIX: nGpuLayers = 0 disables GPU offloading entirely (CPU-only).
      // The default is 99 which tries to use GPU and fails on emulators/
      // devices without Vulkan/OpenCL support or actual GPU hardware.
      // Don't set mainGpu at all when nGpuLayers=0 to avoid GPU misconfiguration.
      final modelParams = ModelParams()
        ..nGpuLayers = 0 // CPU-only: no GPU offloading
        ..mainGpu = -1 // disable GPU selection entirely
        ..splitMode = LlamaSplitMode.none // single device, no splitting
        ..useMemorymap = false // Disable mmap to prevent emulator OOM/SIGKILL crashes
        ..checkTensors = false;

      // Use a slightly larger context window so short documents (passports,
      // invoices) can be queried without hitting the 512‑token limit. 1024 still
      // keeps RAM usage low on small models.
      final contextParams = ContextParams()
        ..nCtx = 1024
        ..nBatch = 1024
        ..nUbatch = 1024
        ..nThreads = 4
        ..nThreadsBatch = 1024;

      final loadCommand = LlamaLoad(
        path: modelPath,
        modelParams: modelParams,
        contextParams: contextParams,
        samplingParams: SamplerParams(),
      );

      _processor = LlamaParent(loadCommand);
      try {
        await _processor!.init();
        debugPrint('Llama initialized successfully');
      } catch (e, stackTrace) {
        debugPrint('ERROR: Llama engine failed to initialize: $e');
        debugPrint('Stacktrace: $stackTrace');
        rethrow;
      }
    } catch (e, stackTrace) {
      debugPrint('ERROR in _ensureEngineReady: $e');
      debugPrint('Stacktrace: $stackTrace');
      _processor = null;
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  Future<String> extractJsonContext(String rawText) async {
    await _ensureEngineReady();

    // Trim input to stay within nCtx=1024 budget; passports and receipts
    // are usually under a couple thousand characters, but we clip to avoid
    // blowing past the window when the raw text contains junk or long noise.
    final trimmed = rawText.length > 1200 ? '${rawText.substring(0, 1200)}...' : rawText;

    final prompt = '''<|im_start|>system
You are a data extraction assistant specialized in passports, IDs and documents. Read the text and output **only** a JSON object. Always include a top‑level "summary" field that contains a short human‑readable sentence describing the most important facts (name, document type, key dates, etc.).

Also include explicit fields for any of the following if you can find them: name, surname, given names, passport_number, id_number, date_of_birth, date_of_expiry, issue_date, nationality, address, place_of_birth, sex, issuing_authority. If you see other useful fields, add them as well.

Example output:
```
{
  "summary":"Passport for John Doe, expires 2026-08-12",
  "name":"John Doe",
  "passport_number":"X1234567",
  "date_of_birth":"1980-03-15",
  "nationality":"GBR"
}
```

Don't wrap values in arrays unless there are multiple entries.
<|im_end|>
<|im_start|>user
Document Text:
"""
$trimmed
"""<|im_end|>
<|im_start|>assistant
```json
''';

    final promptId = await _processor!.sendPrompt(prompt);
    final buffer = StringBuffer();
    bool isComplete = false;

    final sub = _processor!.stream.listen((token) {
      buffer.write(token);
      final soFar = buffer.toString();
      if (soFar.contains('<|im_end|>') || 
         (soFar.length > 5 && soFar.trimRight().endsWith('```'))) {
        isComplete = true;
        _processor!.stop();
      }
    });

    try {
      // Wait for the generation to finish or be stopped
      await _processor!.waitForCompletion(promptId);
    } catch (e) {
      debugPrint('Completion error: $e');
    } finally {
      await sub.cancel();
    }

    String response = buffer.toString();
    try {
      response = response
          .replaceAll('<|im_end|>', '')
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
    } catch (e, stackTrace) {
      debugPrint('ERROR extracting JSON context: $e');
      debugPrint('Stacktrace: $stackTrace');
      rethrow;
    }

    try {
      jsonDecode(response); // validate
      return response;
    } catch (_) {
      // Model produced non-JSON — wrap it gracefully and include the raw text
      // that was sent to the model.  This makes it easier to debug why the
      // assistant failed to produce proper JSON when viewing the chat screen.
      return jsonEncode({
        'summary': trimmed.length > 300 ? '${trimmed.substring(0, 300)}...' : trimmed,
        'raw_text': trimmed,
        'raw_extraction': response,
      });
    }
  }

  Future<String> askQuestion(String jsonContext, String question) async {
    await _ensureEngineReady();

    // Trim lengthy JSON so it doesn't blow past the context window.  The
    // document is already stored on disk, so truncating here is acceptable for
    // an interactive chat; users can rescan if they need more detail.
    String usableJson = jsonContext;
    const maxJsonChars = 1200;
    if (usableJson.length > maxJsonChars) {
      usableJson = usableJson.substring(0, maxJsonChars) + '...';
      debugPrint('askQuestion: trimmed jsonContext to $maxJsonChars chars');
    }

    final prompt = '''<|im_start|>system
You are a helpful assistant. Answer the user's question based strictly on the provided document JSON. Be concise.<|im_end|>
<|im_start|>user
Document JSON:
$usableJson

Question: $question<|im_end|>
<|im_start|>assistant
''';

    final promptId = await _processor!.sendPrompt(prompt);
    final buffer = StringBuffer();
    bool isComplete = false;

    final sub = _processor!.stream.listen((token) {
      if (token.contains('<|im_end|>')) {
        isComplete = true;
        _processor!.stop();
      } else {
        buffer.write(token);
      }
    });

    try {
      await _processor!.waitForCompletion(promptId);
    } catch (e) {
      debugPrint('Completion error in askQuestion: $e');
    } finally {
      await sub.cancel();
    }

    String response = buffer.toString().trim();
    return response;
  }

  void dispose() {
    _processor?.dispose();
    _processor = null;
    _textRecognizer.close();
  }
}