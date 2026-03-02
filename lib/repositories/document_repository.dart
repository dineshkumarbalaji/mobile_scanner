import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/document_model.dart';

class DocumentRepository {
  static const String _documentsKey = 'saved_documents';

  Future<List<Document>> loadDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    final docsJson = prefs.getStringList(_documentsKey) ?? [];
    
    // Sort so newest appears first
    final docs = docsJson.map((jsonStr) => Document.fromJson(jsonStr)).toList();
    docs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return docs;
  }

  Future<void> saveDocument(Document document) async {
    final prefs = await SharedPreferences.getInstance();
    final docsJson = prefs.getStringList(_documentsKey) ?? [];
    
    docsJson.add(document.toJson());
    await prefs.setStringList(_documentsKey, docsJson);
  }

  Future<void> removeDocument(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final docsList = await loadDocuments();
    
    final docToRemove = docsList.firstWhere((doc) => doc.id == id);
    docsList.removeWhere((doc) => doc.id == id);
    
    // Clean up local files (image and json data)
    try {
      if (await File(docToRemove.imagePath).exists()) {
        await File(docToRemove.imagePath).delete();
      }
      if (await File(docToRemove.jsonPath).exists()) {
        await File(docToRemove.jsonPath).delete();
      }
    } catch (e) {
      print("Error deleting document files: $e");
    }
    
    final updatedJsonList = docsList.map((doc) => doc.toJson()).toList();
    await prefs.setStringList(_documentsKey, updatedJsonList);
  }

  Future<void> updateDocument(Document document) async {
    final prefs = await SharedPreferences.getInstance();
    final docsList = await loadDocuments();
    
    final index = docsList.indexWhere((doc) => doc.id == document.id);
    if (index != -1) {
      docsList[index] = document;
      final updatedJsonList = docsList.map((doc) => doc.toJson()).toList();
      await prefs.setStringList(_documentsKey, updatedJsonList);
    }
  }

  Future<List<Document>> searchDocuments(String query) async {
    final docs = await loadDocuments();
    if (query.isEmpty) return docs;
    
    final lowerQuery = query.toLowerCase();
    return docs
        .where((doc) => doc.title.toLowerCase().contains(lowerQuery))
        .toList();
  }
}
