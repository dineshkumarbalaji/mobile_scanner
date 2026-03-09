import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'dart:convert';
import '../models/document_model.dart';
import '../services/ocr_service.dart';
import '../services/chat_service.dart';
import '../services/query_mapper_service.dart';
import '../services/prompt_builder_service.dart';
import '../services/slm_service.dart';
import 'json_viewer_screen.dart';

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

class _ChatScreenState extends State<ChatScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final List<Map<String, String>> _llmHistory = [];
  bool _isTyping = false;
  String _jsonContext = "";
  bool _isLoadingContext = true;
  late final ChatService _chatService;

  late AnimationController _dotsController;

  @override
  void initState() {
    super.initState();
    _chatService = ChatService(
      queryMapperService: QueryMapperService(),
      promptBuilderService: PromptBuilderService(),
      slmService: LocalSlmService(),
    );
    _dotsController = AnimationController(
       vsync: this, 
       duration: const Duration(milliseconds: 1500)
    )..repeat();
    _loadJsonContext();
  }

  Future<void> _loadJsonContext() async {
    try {
      final file = File(widget.document.jsonPath);
      final content = await file.readAsString();
      
      bool isRawText = false;
      String rawText = "";

      // Check if it's the raw text placeholder we save during instant-upload
      try {
         final parsed = jsonDecode(content);
         if (parsed is Map && parsed.length == 1 && parsed.containsKey('raw_text')) {
           isRawText = true;
           rawText = parsed['raw_text'].toString();
         }
      } catch (_) {
         // Could not parse initial JSON, assume it broke or is missing
      }

      String finalContextString = content;

      if (isRawText) {
        setState(() {
           // Provide a specific loading message for SLM Evaluation
           _messages.add(ChatMessage(
             text: "Analyzing document details...", 
             isUser: false
           ));
           _isLoadingContext = true;
        });

        // 1. Try instantaneous Rule-Based Regex Extraction first!
        String? ruleBasedJson = await widget.ocrService.extractJsonWithRules(rawText, widget.document.jsonPath);
        
        if (ruleBasedJson != null) {
           finalContextString = ruleBasedJson;
        } else {
           // 2. Fallback to heavy SLM extraction if Regex couldn't find enough structured data
           setState(() {
             _messages.last = ChatMessage(
               text: "Analyzing document details with deep learning... This may take a minute on your device.", 
               isUser: false
             );
           });
           finalContextString = await widget.ocrService.extractJsonContext(rawText, widget.document.jsonPath);
        }
        
        // Remove the temporary loading message
        setState(() {
           _messages.removeLast();
        });
      }

      String initialMessage;
      // try to parse and render a human summary from the final structured JSON
      try {
        final parsed = jsonDecode(finalContextString);
        String summaryText = '';
        if (parsed is Map) {
          if (parsed['summary'] != null) {
            summaryText = parsed['summary'].toString();
          }
          // build bullet list of other fields
          final buffer = StringBuffer();
          parsed.forEach((key, value) {
            if (key == 'summary' || key == 'raw_text' || key == 'raw_extraction') return;
            buffer.writeln('• $key: $value');
          });
          if (buffer.isNotEmpty) {
            summaryText += '\n' + buffer.toString();
          }
        } else {
          summaryText = finalContextString; // fallback
        }
        initialMessage =
            'Here is the extracted information from the document:\n'
            '$summaryText\n\nHow can I help you?';
      } catch (e) {
        // not valid JSON, just show raw
        initialMessage =
            'Here is the extracted information from the document:\n```json\n$finalContextString\n```\n\nHow can I help you?';
      }

      setState(() {
        _jsonContext = finalContextString;
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
    _dotsController.dispose();
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

  void _clearHistory() {
    setState(() {
      _llmHistory.clear();
      // Keep only the initial context message
      if (_messages.isNotEmpty) {
        final firstMessage = _messages.first;
        _messages.clear();
        _messages.add(firstMessage);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Chat history cleared")),
    );
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
      final answer = await _chatService.askQuestion(
        jsonContext: _jsonContext, 
        question: text
      );
      debugPrint('Chat: model -> $answer');
      
      setState(() {
        _llmHistory.add({'role': 'user', 'content': text});
        _llmHistory.add({'role': 'assistant', 'content': answer});
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

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: AnimatedBuilder(
          animation: _dotsController,
          builder: (context, child) {
            String dots = "";
            int step = (_dotsController.value * 4).floor();
            for (var i = 0; i < step; i++) {
              dots += ".";
            }
            return Text('AI is reasoning$dots', style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey));
          },
        ),
      ),
    );
  }

  void _showImagePreview() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.file(File(widget.document.imagePath)),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.black54),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.document.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.image),
            onPressed: _showImagePreview,
            tooltip: 'View Document Image',
          ),
          IconButton(
            icon: const Icon(Icons.data_object),
            onPressed: () {
               Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => JsonViewerScreen(document: widget.document),
                ),
               );
            },
            tooltip: 'View Extracted Data',
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _isTyping ? null : _clearHistory,
            tooltip: 'Clear History',
          ),
        ],
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
          if (_isTyping) _buildTypingIndicator(),
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
