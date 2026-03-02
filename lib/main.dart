import 'package:flutter/material.dart';
import 'ui/document_list_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // NOTE: Do NOT call OcrService().extractJsonContext() here.
  // Model initialization is heavy (~130MB load) and must happen lazily
  // on a background isolate, not on the main thread at startup.
  runApp(const MobileScannerApp());
}

class MobileScannerApp extends StatelessWidget {
  const MobileScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GLM-OCR Scanner',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: DocumentListScreen(),
    );
  }
}