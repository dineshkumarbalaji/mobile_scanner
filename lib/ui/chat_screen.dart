import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'dart:convert';
import '../models/document_model.dart';
import '../services/ocr_service.dart';

class ChatMessage {
  final String text;
  final bool isUser;

  ChatMessage({required this.text, required this.isUser});
}

class ChatScreen extends StatefulWidget {
  final Document document;
  final OcrService ocrService;

  const ChatScreen({super.key, required this.document, required this.ocrService});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isTyping = false;
  String _jsonContext = "";
  bool _isLoadingContext = true;

  @override
  void initState() {
    super.initState();
    _loadJsonContext();
  }

  Future<void> _loadJsonContext() async {
    try {
      final file = File(widget.document.jsonPath);
      final content = await file.readAsString();
      String initialMessage;
      // try to parse and render a human summary
      try {
        final parsed = jsonDecode(content);
        String summaryText = '';
        if (parsed is Map) {
          if (parsed['summary'] != null) {
            summaryText = parsed['summary'].toString();
          }
          // build bullet list of other fields
          final buffer = StringBuffer();
          parsed.forEach((key, value) {
            if (key == 'summary') return;
            buffer.writeln('• $key: $value');
          });
          if (buffer.isNotEmpty) {
            summaryText += '\n' + buffer.toString();
          }
        } else {
          summaryText = content; // fallback
        }
        initialMessage =
            'Here is the extracted information from the document:\n'
            '$summaryText\n\nHow can I help you?';
      } catch (e) {
        // not valid JSON, just show raw
        initialMessage =
            'Here is the extracted information from the document:\n```json\n$content\n```\n\nHow can I help you?';
      }

      setState(() {
        _jsonContext = content;
        _isLoadingContext = false;
        _messages.add(ChatMessage(text: initialMessage, isUser: false));
      });
    } catch (e) {
      setState(() {
        _isLoadingContext = false;
        _messages.add(ChatMessage(text: "Failed to load document context: $e", isUser: false));
      });
    }
  }

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _isLoadingContext || _isTyping) return;

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isTyping = true;
    });
    debugPrint('Chat: user -> $text');
    
    _chatController.clear();
    _scrollToBottom();

    try {
      final answer = await widget.ocrService.askQuestion(_jsonContext, text);
      debugPrint('Chat: model -> $answer');
      setState(() {
        _messages.add(ChatMessage(text: answer, isUser: false));
      });
    } catch (e) {
      final errMsg = "Error: Could not get an answer. ($e)";
      debugPrint('Chat: error -> $e');
      setState(() {
        _messages.add(ChatMessage(text: errMsg, isUser: false));
      });
    } finally {
      setState(() {
        _isTyping = false;
      });
      _scrollToBottom();
    }
  }

  Widget _buildMessageBubble(ChatMessage message) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: message.isUser ? Colors.blue[100] : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: MarkdownBody(
          data: message.text,
          selectable: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.document.title),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoadingContext
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8.0),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return _buildMessageBubble(_messages[index]);
                    },
                  ),
          ),
          if (_isTyping)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('AI is reasoning...', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  offset: const Offset(0, -1),
                  blurRadius: 5,
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chatController,
                      enabled: !_isLoadingContext,
                      decoration: const InputDecoration(
                        hintText: 'Ask about the document...',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: (_isTyping || _isLoadingContext) ? null : _sendMessage,
                    icon: const Icon(Icons.send, color: Colors.blue),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
