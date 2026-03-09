import 'dart:convert';

class PromptBuilderService {
  String buildPrompt({
    required Map<String, dynamic> jsonData,
    required String userQuestion,
  }) {
    final jsonText = const JsonEncoder.withIndent('  ').convert(jsonData);

    return '''<|im_start|>system
You are a strict data extraction assistant. You MUST strictly follow these rules:
- Answer ONLY from the provided JSON Data.
- Make NO assumptions.
- Use NO external knowledge.
- Do NO guessing.
- If the answer is missing, say EXACTLY: "Not found in document data".
- Keep your answer under 25 words unless specifically asked for more.
Be extremely concise and factual. Do not hallucinate.

JSON:
$jsonText<|im_end|>
<|im_start|>user
$userQuestion<|im_end|>
<|im_start|>assistant
''';
  }
}
