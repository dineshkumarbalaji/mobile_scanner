import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:convert' as convert;
import '../services/ocr_service.dart';
import '../models/document_model.dart';
import 'package:path_provider/path_provider.dart';
import '../repositories/document_repository.dart';
import 'result_screen.dart';

class PreviewScreen extends StatefulWidget {
  final String imagePath;

  const PreviewScreen({super.key, required this.imagePath});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  late OcrService _ocrService;
  late DocumentRepository _repository;
  bool _isProcessing = false;
  String _processingStatus = "Ready";

  @override
  void initState() {
    super.initState();
    _ocrService = OcrService();
    _repository = DocumentRepository();
  }

  Future<void> _processImage() async {
    setState(() {
      _isProcessing = true;
      _processingStatus = "Extracting text...";
    });

    try {
      final imageFile = File(widget.imagePath);

      // 1. Extract raw text using ML Kit OCR
      setState(() {
        _processingStatus = "Running OCR...";
      });
      final ocrResult = await _ocrService.extractText(imageFile);

      // 2. Extract JSON context using SLM & 3. Save document locally
      setState(() {
        _processingStatus = "Saving document...";
      });

      final dir = await getApplicationDocumentsDirectory();
      final docId = DateTime.now().millisecondsSinceEpoch.toString();

      final localImagePath = '${dir.path}/image_$docId.jpg';
      await imageFile.copy(localImagePath);

      final localJsonPath = '${dir.path}/data_$docId.json';

      // Instantly save RAW text as a placeholder into the JSON file
      final rawData = jsonEncode({
         "raw_text": ocrResult.text 
      });
      await File(localJsonPath).writeAsString(rawData);

      // Create and save document model
      final newDoc = Document(
        id: docId,
        title: "Scan $docId",
        imagePath: localImagePath,
        jsonPath: localJsonPath,
        createdAt: DateTime.now(),
      );

      await _repository.saveDocument(newDoc);

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Document processed and saved successfully")),
      );

      // Navigate back to the home/list screen instead of result screen
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      setState(() {
        _processingStatus = "Error: $e";
        _isProcessing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Processing failed: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Preview')),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.grey[300],
              child: Image.file(
                File(widget.imagePath),
                fit: BoxFit.cover,
              ),
            ),
          ),
          if (_isProcessing)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.blue[100],
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_processingStatus),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _processImage,
                    icon: const Icon(Icons.check),
                    label: const Text('Process'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
