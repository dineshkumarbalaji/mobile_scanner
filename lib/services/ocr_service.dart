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
        for (final lib in ['libomp.so', 'libggml-base.so', 'libggml-cpu.so', 'libggml.so']) {
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

      // Use a smaller context window (1024) to drastically speed up processing
      // on CPU devices, since Passports and most IDs don't have that much text.
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

  /// Attempts to build a structured JSON response using entirely
  /// zero-shot Regex rules to skip the slow SLM evaluation time on Emulator.
  Future<String?> extractJsonWithRules(String rawText, String jsonSavePath) async {
    final Map<String, dynamic> extractedData = {};
    
    // Helper to find regex matches and add them to the map
    void extractPattern(String key, RegExp regex) {
       final match = regex.firstMatch(rawText);
       if (match != null && match.groupCount >= 1) {
          extractedData[key] = match.group(1)!.trim();
       }
    }

    // --- MRZ (Machine Readable Zone) Extraction ---
    // This is the most reliable block on a passport!
    // Line 1: P<GBRDOE<<JOHN<<<<<<<<<<<<<
    final mrzNamePattern = RegExp(r'P[<A-Z][A-Z<]{3}([A-Z<]+?)<<([A-Z<]+)');
    final mrzNameMatch = mrzNamePattern.firstMatch(rawText);
    if (mrzNameMatch != null) {
      extractedData['surname'] = mrzNameMatch.group(1)?.replaceAll('<', ' ').trim();
      extractedData['given names'] = mrzNameMatch.group(2)?.replaceAll('<', ' ').trim();
      extractedData['doc_type'] = 'Passport';
    } else {
      extractPattern('name', RegExp(r'(?:name|surname)[\s:]+([A-Z\s]{4,30})\b', caseSensitive: false));
    }

    // Line 2: 9992049000GBR9501016F2911272<<<<<<<<<<<<<<06
    // [9 chars ID][1 char check][3 chars Country][6 chars DOB][1 char check][1 char Sex][6 chars Expiry]
    final mrzDataPattern = RegExp(r'([A-Z0-9<]{9})\d[A-Z]{3}(\d{6})\d([MF<])(\d{6})');
    final mrzDataMatch = mrzDataPattern.firstMatch(rawText);
    
    if (mrzDataMatch != null) {
       extractedData['passport_number'] = mrzDataMatch.group(1)?.replaceAll('<', '');
       
       // Format YYMMDD into something readable if possible, or just raw
       final rawDob = mrzDataMatch.group(2);
       if (rawDob != null && rawDob.length == 6) {
           extractedData['date_of_birth'] = '${rawDob.substring(4,6)}/${rawDob.substring(2,4)}/19${rawDob.substring(0,2)}'; // Assumes 19XX for simplicity of demo
       }

       extractedData['sex'] = mrzDataMatch.group(3)?.replaceAll('<', 'X');

       final rawExp = mrzDataMatch.group(4);
       if (rawExp != null && rawExp.length == 6) {
           extractedData['date_of_expiry'] = '${rawExp.substring(4,6)}/${rawExp.substring(2,4)}/20${rawExp.substring(0,2)}';
       }
    } else {
       // Fallback for non-passports
       extractPattern('passport_number', RegExp(r'(?:passport no|document no|number)[\s:\.]*([A-Z0-9]{8,9})\b', caseSensitive: false));
       extractPattern('sex', RegExp(r'(?:sex|gender)[\s:\.]*\b([MF])\b', caseSensitive: false));
    }

    // --- Dates Extraction ---
    // Handles traditional DD/MM/YYYY and UK Passport formats: "27 NOV / NOV 19" or "DD MMM / MMM YY"
    final dateRegExp = RegExp(r'\b(\d{2}\s+(?:JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)(?:\s+/\s+[A-Z]{3})?\s+\d{2,4}|\d{2}/\d{2}/\d{4})\b', caseSensitive: false);
    final dates = dateRegExp.allMatches(rawText).map((m) => m.group(1)!.replaceAll(RegExp(r'\s+/\s+[A-Z]{3}\s+'), ' ')).toList(); // Clean up the slash
    
    if (dates.isNotEmpty) {
       if (!extractedData.containsKey('date_of_birth')) {
          extractPattern('date_of_birth', RegExp(r'(?:dob|birth|born)[\s:\.]+([0-9A-Za-z\s/]{8,15})\b', caseSensitive: false));
          extractedData.putIfAbsent('date_of_birth', () => dates.first);
       }
       
       // Issue Date (often the middle date on UK passports if 3 dates exist)
       extractPattern('date_of_issue', RegExp(r'(?:issue|issued)[\s:\.]+([0-9A-Za-z\s/]{8,15})\b', caseSensitive: false));
       if (!extractedData.containsKey('date_of_issue') && dates.length >= 3) {
          extractedData['date_of_issue'] = dates[1]; 
       }

       if (!extractedData.containsKey('date_of_expiry')) {
          extractPattern('date_of_expiry', RegExp(r'(?:expiry|expires)[\s:\.]+([0-9A-Za-z\s/]{8,15})\b', caseSensitive: false));
          if (!extractedData.containsKey('date_of_expiry') && dates.length > 1) {
             extractedData['date_of_expiry'] = dates.last; 
          }
       }
    }

    extractPattern('nationality', RegExp(r'(?:nationality|code)[\s:\.]*\b([A-Z]{3})\b', caseSensitive: false)); // GBR, USA, etc.

    // --- Place of Birth Extraction ---
    extractPattern('place_of_birth', RegExp(r'(?:place of birth|lieu de naissance)[^\n]*\n\s*(?:[A-Z]\s+)?([A-Z ]{3,30})\b', caseSensitive: false));
    if (!extractedData.containsKey('place_of_birth')) {
       extractPattern('place_of_birth', RegExp(r'(?:place of birth|lieu de naissance)[\s:\.]+([A-Z ]{3,30})\b', caseSensitive: false));
    }

    // --- Authority Extraction ---
    extractPattern('authority', RegExp(r'(?:authority|autorit)[^\n]*\n\s*([A-Z0-9]{3,20})\b', caseSensitive: false));
    if (!extractedData.containsKey('authority')) {
       extractPattern('authority', RegExp(r'(?:authority|autorit)[\s:\.]+([A-Z0-9]{3,20})\b', caseSensitive: false));
    }

    // If we couldn't confidently find at least two pieces of info, return null to fallback to SLM
    if (extractedData.length < 2) {
      return null;
    }

    // Build the "Summary" block required by the UI
    final summaryBuffer = StringBuffer("Automatically extracted via rules:\n");
    extractedData.forEach((key, value) {
      summaryBuffer.writeln("$key: $value");
    });
    extractedData['summary'] = summaryBuffer.toString().trim();
    extractedData['raw_text'] = rawText;

    // Write instantly to disk
    final finalJson = jsonEncode(extractedData);
    final file = File(jsonSavePath);
    await file.writeAsString(finalJson);
    
    return finalJson;
  }

  Future<String> extractJsonContext(String rawText, String jsonSavePath) async {
    await _ensureEngineReady();

    // Aggressively Trim input to stay within nCtx=1024 budget. 
    // Passports/IDs only have a few lines of relevant text anyway.
    final trimmed = rawText.length > 1500  ? '${rawText.substring(0, 1500)}...' : rawText;

    final prompt = '''<|im_start|>system
You are a data extraction assistant. Read the text and output **only** a JSON object. Provide a brief human-readable "summary" field. Then, pull out the most important 3 or 4 structured data fields you can identify (like name, dates, ID numbers) using logical keys. Keep it extremely concise.
<|im_end|>
<|im_start|>user
Document Text:
"""
$trimmed
"""<|im_end|>
<|im_start|>assistant
{'''; // Pre-seeding trick to get cleaner JSON output (forces it to start right into JSON)

    debugPrint('Sending prompt to LLM (Length: ${prompt.length} chars)...');
    final promptId = await _processor!.sendPrompt(prompt);
    debugPrint('Prompt sent! ID: $promptId');
    
    final buffer = StringBuffer();
    // Add the open brace we pre-seeded to the buffer so the final string parses correctly
    buffer.write('{');
    bool isComplete = false;

    final sub = _processor!.stream.listen((token) {
      debugPrint('LLM Token: $token');
      buffer.write(token);
      final soFar = buffer.toString();
      if (soFar.contains('<|im_end|>') || 
         (soFar.length > 5 && soFar.trimRight().endsWith('```'))) {
        isComplete = true;
        _processor!.stop();
      }
    });

    try {
      debugPrint('Waiting for completion (with 60-second timeout)...');
      // Wait for the generation to finish or be stopped, but don't hang forever
      // on incredibly slow emulators!
      await _processor!.waitForCompletion(promptId).timeout(const Duration(seconds: 45));
      debugPrint('Completion finished naturally!');
    } on TimeoutException {
      debugPrint('Completion timed out (45s elapsed). Emulator is likely too slow for full SLM extraction.');
      _processor!.stop();
      // Artificial delay to let the stop signal propagate
      await Future.delayed(const Duration(milliseconds: 500));
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

    String finalJson;
    try {
      jsonDecode(response); // validate
      finalJson = response;
    } catch (_) {
      // Model produced non-JSON — wrap it gracefully and include the raw text
      // that was sent to the model.  This makes it easier to debug why the
      // assistant failed to produce proper JSON when viewing the chat screen.
      finalJson = jsonEncode({
        'summary': trimmed.length > 300 ? '${trimmed.substring(0, 300)}...' : trimmed,
        'raw_text': trimmed,
        'raw_extraction': response,
      });
    }

    // Atomically write it here within the service
    final file = File(jsonSavePath);
    await file.writeAsString(finalJson);
    return finalJson;
  }

  Future<String> askQuestion(
      String jsonContext, String question,
      {List<Map<String, String>> chatHistory = const [],
      int maxHistoryTurns = 2}) async {
    
    // --- FAST PATH: Dictionary Lookup ---
    try {
      final parsedJson = jsonDecode(jsonContext);
      if (parsedJson is Map<String, dynamic>) {
        final q = question.toLowerCase();
        
        // Helper to check if question contains keywords and JSON has a matching key
        String? check(List<String> keywords, List<String> jsonKeys) {
          if (keywords.any((kw) => q.contains(kw))) {
             for (final key in jsonKeys) {
               if (parsedJson.containsKey(key)) {
                 return parsedJson[key].toString();
               }
             }
             return "I couldn't find that specific information in the document.";
          }
          return null;
        }

        // 1. Name
        if (q.contains('surname') || q.contains('last name')) {
          if (parsedJson.containsKey('surname')) return parsedJson['surname'].toString();
          if (parsedJson.containsKey('last_name')) return parsedJson['last_name'].toString();
          return "I couldn't find that specific information in the document.";
        }
        if (q.contains('first name') || q.contains('given name') || q.contains('given names')) {
          if (parsedJson.containsKey('given names')) return parsedJson['given names'].toString();
          if (parsedJson.containsKey('given_name')) return parsedJson['given_name'].toString();
          if (parsedJson.containsKey('first_name')) return parsedJson['first_name'].toString();
          return "I couldn't find that specific information in the document.";
        }
        if (q.contains('name')) {
          if (parsedJson.containsKey('name')) return parsedJson['name'].toString();
          if (parsedJson.containsKey('full name')) return parsedJson['full name'].toString();
          if (parsedJson.containsKey('full_name')) return parsedJson['full_name'].toString();
          
          String combined = "";
          if (parsedJson.containsKey('given names')) combined += parsedJson['given names'].toString() + " ";
          if (parsedJson.containsKey('first_name')) combined += parsedJson['first_name'].toString() + " ";
          if (parsedJson.containsKey('surname')) combined += parsedJson['surname'].toString() + " ";
          if (parsedJson.containsKey('last_name')) combined += parsedJson['last_name'].toString();
          combined = combined.trim();
          if (combined.isNotEmpty) return combined;
          
          return "I couldn't find that specific information in the document.";
        }

        // 2. Place of Birth (Ensure this is checked before generic 'birth')
        var result = check(['place of birth', 'birth place', 'born in', 'where'], ['place_of_birth']);
        if (result != null) return result;

        // 3. Date of Birth
        result = check(['dob', 'birth', 'born', 'when'], ['date_of_birth', 'dob', 'birth_date']);
        if (result != null) return result;

        // 4. Document/Passport Number
        result = check(['passport number', 'id number', 'document number', 'number'], ['passport_number', 'id_number', 'document_number']);
        if (result != null) return result;

        // 5. Expiry
        result = check(['expire', 'expiry', 'valid until'], ['date_of_expiry', 'expiry_date', 'expiration']);
        if (result != null) return result;

        // 6. Nationality/Country
        result = check(['nationality', 'country', 'citizen'], ['nationality', 'country', 'citizenship']);
        if (result != null) return result;
        
        // 7. Sex/Gender
        result = check(['sex', 'gender'], ['sex', 'gender']);
        if (result != null) return result;
      }
    } catch (_) {
      // If JSON parsing fails, just fall through to the SLM
    }
    // --- END FAST PATH ---

    await _ensureEngineReady();

    final promptBuilder = StringBuffer();
    // 1. System Instruction & Context (Heavily trimmed for speed)
    promptBuilder.writeln('<|im_start|>system');
    promptBuilder.writeln(
        'You are a helpful assistant. Use the JSON data below to answer the user. Keep answers very short.');
    
    // Trim context if it's too large to save CPU evaluation time
    final trimmedContext = jsonContext.length > 1500 ? '${jsonContext.substring(0, 1500)}...' : jsonContext;

    promptBuilder.writeln('JSON Data:\n$trimmedContext<|im_end|>');

    // 2. Chat History (Keep it extremely short to avoid blowing context windows)
    final recentHistory = chatHistory.length > maxHistoryTurns * 2
        ? chatHistory.sublist(chatHistory.length - maxHistoryTurns * 2)
        : chatHistory;

    for (var msg in recentHistory) {
      if (msg['role'] == 'user') {
        promptBuilder.writeln('<|im_start|>user\n${msg['content']}<|im_end|>');
      } else {
        promptBuilder.writeln('<|im_start|>assistant\n${msg['content']}<|im_end|>');
      }
    }// 3. Current Question
    promptBuilder.writeln('<|im_start|>user');
    promptBuilder.writeln('$question<|im_end|>');
    promptBuilder.writeln('<|im_start|>assistant');

    final prompt = promptBuilder.toString();

    debugPrint('Sending Chat prompt to LLM (Length: ${prompt.length} chars)...');
    final promptId = await _processor!.sendPrompt(prompt);
    final buffer = StringBuffer();
    bool isComplete = false;

    final sub = _processor!.stream.listen((token) {
      if (token.contains('<|im_end|>') || 
         (token.length > 5 && token.trimRight().endsWith('```'))) {
        isComplete = true;
        _processor!.stop();
      } else {
        buffer.write(token);
      }
    });

    try {
      debugPrint('Waiting for Chat completion (with 60-second timeout)...');
      await _processor!.waitForCompletion(promptId).timeout(const Duration(seconds: 45));
      debugPrint('Chat completion finished!');
    } on TimeoutException {
      debugPrint('Chat completion timed out (45s elapsed). Emulator is likely too slow.');
      _processor!.stop();
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      debugPrint('Completion error in askQuestion: $e');
    } finally {
      await sub.cancel();
    }

    String response = buffer.toString().trim();
    if (response.isEmpty) {
       return "I'm sorry, my reasoning process timed out or was interrupted. Please try again or use a faster device.";
    }
    return response;
  }

  void dispose() {
    _processor?.dispose();
    _processor = null;
    _textRecognizer.close();
  }
}