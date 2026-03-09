import 'dart:convert';
import 'package:mobile_scanner/services/query_mapper_service.dart';
import 'package:mobile_scanner/services/prompt_builder_service.dart';
import 'package:mobile_scanner/services/slm_service.dart';
import 'package:mobile_scanner/services/fast_path_service.dart';

class ChatService {
  final QueryMapperService queryMapperService;
  final PromptBuilderService promptBuilderService;
  final SlmService slmService;
  final FastPathService fastPathService;

  ChatService({
    required this.queryMapperService,
    required this.promptBuilderService,
    required this.slmService,
    FastPathService? fastPathService,
  }) : fastPathService = fastPathService ?? FastPathService();

  Future<String> askQuestion({
    required String jsonContext,
    required String question,
  }) async {
    Map<String, dynamic> documentJson = {};
    try {
      final parsed = jsonDecode(jsonContext);
      if (parsed is Map<String, dynamic>) {
        documentJson = parsed;
      }
    } catch (_) {}

    final keys = queryMapperService.detectRelevantKeys(question);

    // --- Layer 1: Fast-path rule evaluation (no SLM needed) ---
    // resolved  → field found: return instantly.
    // notFound  → field known but missing: return "Not found" instantly (no SLM).
    // unknown   → open-ended question: fall through to SLM.
    final fastResult = fastPathService.resolve(
      documentJson: documentJson,
      keys: keys,
    );

    switch (fastResult.outcome) {
      case FastPathOutcome.resolved:
      case FastPathOutcome.notFound:
        return fastResult.answer!;
      case FastPathOutcome.unknown:
        break; // fall through to SLM
    }

    // --- Layer 2: Filtered JSON -> Strict Prompt -> On-Device SLM ---
    // Only reached for genuinely open-ended questions with no field mapping.
    // Scope the context to summary-only to keep prompt small and inference fast.
    Map<String, dynamic> filteredJson = {};

    if (documentJson.containsKey('summary')) {
      // Pass only the summary field for open-ended questions.
      filteredJson['summary'] = documentJson['summary'];
    } else {
      // Build a lightweight view: exclude raw_text and raw_extraction blobs.
      documentJson.forEach((k, v) {
        if (k != 'raw_text' && k != 'raw_extraction') {
          filteredJson[k] = v;
        }
      });
    }

    if (filteredJson.isEmpty) {
      return 'Not found in document data.';
    }

    final prompt = promptBuilderService.buildPrompt(
      jsonData: filteredJson,
      userQuestion: question,
    );

    final answer = await slmService.generateResponse(prompt);
    if (answer.isEmpty) {
      return 'Not found in document data.';
    }
    return answer;
  }
}
