import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import '../models/document_model.dart';
import '../repositories/document_repository.dart';
import '../services/ocr_service.dart';
import 'chat_screen.dart';

class DocumentListScreen extends StatefulWidget {
  @override
  _DocumentListScreenState createState() => _DocumentListScreenState();
}

class _DocumentListScreenState extends State<DocumentListScreen> {
  final DocumentRepository _repository = DocumentRepository();
  final OcrService _ocrService = OcrService();
  List<Document> _documents = [];
  List<Document> _filteredDocuments = [];
  bool _isLoading = true;
  bool _isProcessingDocument = false;
  String _processingStatus = "";
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _testModelExtraction() async {
    print("================== SLM TEST START ==================");
    print("Testing bundled model extraction from rootBundle...");
    try {
      final res = await _ocrService.extractJsonContext("Mock OCR Document Text: Invoice ID: 59392, Total Amount: \$250.00, Date: 2023-10-25");
      print("================== SLM TEST OUTPUT ==================");
      print(res);
      print("================== SLM TEST END ==================");
    } catch (e) {
      print("================== SLM TEST FAILED ==================");
      print(e);
    }
  }

  Future<void> _loadDocuments() async {
    final docs = await _repository.loadDocuments();
    setState(() {
      _documents = docs;
      _filteredDocuments = docs;
      _isLoading = false;
    });
  }

  Future<void> _searchDocuments(String query) async {
    setState(() {
      _searchQuery = query;
    });
    final results = await _repository.searchDocuments(query);
    setState(() {
      _filteredDocuments = results;
    });
  }

  Future<void> _processNewDocument(File imageFile) async {
    setState(() {
      _isProcessingDocument = true;
      _processingStatus = "Running ML Kit OCR...";
    });

    try {
      // 1. Extract raw text
      final ocrResult = await _ocrService.extractText(imageFile);
      
      setState(() {
        _processingStatus = "Running SLM to extract JSON data (This may take a minute based on your device)...";
      });

      // 2. Feed text to SLM, get JSON string
      final jsonContext = await _ocrService.extractJsonContext(ocrResult.text);

      setState(() {
        _processingStatus = "Saving Document Local Data...";
      });

      // 3. Save Image & JSON Locally
      final dir = await getApplicationDocumentsDirectory();
      final docId = DateTime.now().millisecondsSinceEpoch.toString();
      
      final localImagePath = '${dir.path}/image_$docId.jpg';
      await imageFile.copy(localImagePath);

      final localJsonPath = '${dir.path}/data_$docId.json';
      final jsonFile = File(localJsonPath);
      await jsonFile.writeAsString(jsonContext);

      // Extract a better title from the JSON if available
      String documentTitle = "Scan $docId";
      try {
        final jsonData = jsonDecode(jsonContext);
        if (jsonData is Map && jsonData.containsKey('summary')) {
          documentTitle = jsonData['summary'].toString().substring(0, 50);
          if (jsonData['summary'].toString().length > 50) {
            documentTitle += '...';
          }
        }
      } catch (_) {
        // Fallback to default title if JSON parsing fails
      }

      // Create model
      final newDoc = Document(
        id: docId,
        title: documentTitle,
        imagePath: localImagePath,
        jsonPath: localJsonPath,
        createdAt: DateTime.now(),
      );

      // 4. Save to Repository and refresh UI
      await _repository.saveDocument(newDoc);
      await _loadDocuments();

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() {
        _isProcessingDocument = false;
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);
    
    if (pickedFile != null) {
      final file = File(pickedFile.path);
      await _processNewDocument(file);
    }
  }

  void _showImageSourceOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt),
                title: Text('Take a Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library),
                title: Text('Upload from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteDocument(String id) async {
    await _repository.removeDocument(id);
    await _loadDocuments();
  }

  Future<void> _renameDocument(Document document) async {
    final controller = TextEditingController(text: document.title);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rename Document'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: 'Document Title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final updated = Document(
                  id: document.id,
                  title: controller.text,
                  imagePath: document.imagePath,
                  jsonPath: document.jsonPath,
                  createdAt: document.createdAt,
                );
                await _repository.updateDocument(updated);
                await _loadDocuments();
                Navigator.pop(context);
              }
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('My Documents (${_documents.length})'),
        elevation: 0,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: TextField(
                  onChanged: _searchDocuments,
                  decoration: InputDecoration(
                    hintText: 'Search documents...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              // Document list
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator())
                    : _filteredDocuments.isEmpty
                        ? Center(
                            child: Text(
                              _searchQuery.isEmpty
                                  ? 'No documents saved yet. Scan one!'
                                  : 'No documents match your search.',
                            ),
                          )
                        : ListView.builder(
                            itemCount: _filteredDocuments.length,
                            itemBuilder: (context, index) {
                              final document = _filteredDocuments[index];
                              return Card(
                                margin: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                child: ListTile(
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: Image.file(
                                      File(document.imagePath),
                                      width: 50,
                                      height: 50,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  title: Text(document.title),
                                  subtitle: Text(
                                    'Created: ${document.createdAt.toString().split(' ')[0]}',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  trailing: PopupMenuButton(
                                    itemBuilder: (context) => [
                                      PopupMenuItem(
                                        child: Text('Rename'),
                                        value: 'rename',
                                      ),
                                      PopupMenuItem(
                                        child: Text(
                                          'Delete',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                        value: 'delete',
                                      ),
                                    ],
                                    onSelected: (value) {
                                      if (value == 'rename') {
                                        _renameDocument(document);
                                      } else if (value == 'delete') {
                                        _deleteDocument(document.id);
                                      }
                                    },
                                  ),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ChatScreen(
                                          document: document,
                                          ocrService: _ocrService,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
          if (_isProcessingDocument)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 20),
                      Text(
                        _processingStatus,
                        style: TextStyle(color: Colors.white, fontSize: 16),
                        textAlign: TextAlign.center,
                      )
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isProcessingDocument ? null : _showImageSourceOptions,
        child: Icon(Icons.add_a_photo),
        tooltip: 'Add Document',
      ),
    );
  }
}
