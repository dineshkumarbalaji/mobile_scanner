import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/ocr_result.dart';
import '../models/document_model.dart';
import '../services/ocr_service.dart';
import 'chat_screen.dart';

class ResultScreen extends StatelessWidget {
  final OcrResult ocrResult;
  final Document document;

  const ResultScreen({
    super.key,
    required this.ocrResult,
    required this.document,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OCR Result'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ChatScreen(
                    document: document,
                    ocrService: OcrService(),
                  ),
                ),
              );
            },
            tooltip: 'Chat about document',
          ),
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () {
              // Pop back to document list
              Navigator.of(context).popUntil(
                (route) => route.isFirst,
              );
            },
            tooltip: 'Go home',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Extraction Complete',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'Confidence: ${(ocrResult.confidence * 100).toStringAsFixed(1)}%',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Extracted Text:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Container(
                padding: const EdgeInsets.all(12),
                width: double.infinity,
                child: MarkdownBody(
                  data: ocrResult.text,
                  selectable: true,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (ocrResult.structuredData != null) ...[
              const Text(
                'Structured Data:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  width: double.infinity,
                  child: Text(
                    ocrResult.structuredData!,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}
