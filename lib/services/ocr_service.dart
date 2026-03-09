import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/ocr_result.dart';
import 'slm_service.dart';

class OcrService {
  final TextRecognizer _textRecognizer =
  TextRecognizer(script: TextRecognitionScript.latin);

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
      extractedData['given_names'] = mrzNameMatch.group(2)?.replaceAll('<', ' ').trim();
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
    final slm = LocalSlmService();

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
{'''; 

    debugPrint('Sending prompt to LLM (Length: ${prompt.length} chars)...');
    String response = await slm.generateResponse(prompt, timeoutSeconds: 60);
    
    // add pre-seeded brace back
    response = '{$response';

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

  void dispose() {
    _textRecognizer.close();
  }
}