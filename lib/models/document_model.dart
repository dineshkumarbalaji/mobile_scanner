import 'dart:convert';

class Document {
  final String id;
  final String title;
  final String imagePath;
  final String jsonPath;
  final DateTime createdAt;

  Document({
    required this.id,
    required this.title,
    required this.imagePath,
    required this.jsonPath,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'imagePath': imagePath,
      'jsonPath': jsonPath,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Document.fromMap(Map<String, dynamic> map) {
    return Document(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      imagePath: map['imagePath'] ?? '',
      jsonPath: map['jsonPath'] ?? '',
      createdAt: DateTime.parse(map['createdAt']),
    );
  }

  String toJson() => json.encode(toMap());

  factory Document.fromJson(String source) => Document.fromMap(json.decode(source));
}
