import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:convert';
import '../models/document_model.dart';
import 'package:flutter/services.dart';

class JsonViewerScreen extends StatefulWidget {
  final Document document;

  const JsonViewerScreen({super.key, required this.document});

  @override
  State<JsonViewerScreen> createState() => _JsonViewerScreenState();
}

class _JsonViewerScreenState extends State<JsonViewerScreen> {
  String _jsonString = "";
  bool _isLoading = true;
  String _errorMessage = "";

  @override
  void initState() {
    super.initState();
    _loadJson();
  }

  Future<void> _loadJson() async {
    try {
      final file = File(widget.document.jsonPath);
      if (await file.exists()) {
        final content = await file.readAsString();
        
        // Try to pretty-print if it's valid JSON
        try {
          final decoded = jsonDecode(content);
          final encoder = JsonEncoder.withIndent('  ');
          _jsonString = encoder.convert(decoded);
        } catch (_) {
          _jsonString = content; // Fallback to raw string
        }
      } else {
        _errorMessage = "Data file not found.";
      }
    } catch (e) {
      _errorMessage = "Failed to load data: $e";
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _copyToClipboard() {
    if (_jsonString.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: _jsonString));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Copied to clipboard")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Extracted Data'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: _isLoading || _errorMessage.isNotEmpty ? null : _copyToClipboard,
            tooltip: 'Copy data',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.red)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: SelectableText(
                      _jsonString,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                    ),
                  ),
                ),
    );
  }
}
