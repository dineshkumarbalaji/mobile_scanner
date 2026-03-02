class OcrResult {
  final String text;
  final String? structuredData; // JSON or Markdown
  final double confidence;

  OcrResult({
    required this.text,
    this.structuredData,
    this.confidence = 0.0,
  });

  factory OcrResult.fromJson(Map<String, dynamic> json) {
    return OcrResult(
      text: json['text'] ?? '',
      structuredData: json['structured_data'],
      confidence: json['confidence'] ?? 0.0,
    );
  }
}
