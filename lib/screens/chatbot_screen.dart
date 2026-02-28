import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/gemini_service.dart';

class ChatbotScreen extends ConsumerStatefulWidget {
  const ChatbotScreen({super.key});

  @override
  ConsumerState<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends ConsumerState<ChatbotScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  bool _isLoading = false;

  void _sendMessage() async {
    final text = _controller.text;
    if (text.isEmpty) return;

    setState(() {
      _messages.add({"role": "user", "text": text});
      // Add a placeholder for AI response
      _messages.add({"role": "ai", "text": ""});
      _controller.clear();
      _isLoading = true;
    });

    final geminiService = ref.read(geminiServiceProvider);
    final responseStream = geminiService.sendMessageStream(text);

    int aiMessageIndex = _messages.length - 1;

    await for (final chunk in responseStream) {
      if (mounted) {
        setState(() {
          _messages[aiMessageIndex]["text"] =
              (_messages[aiMessageIndex]["text"] ?? "") + chunk;
          _isLoading = false; // Turn off loading once bytes arrive
        });
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Disaster Assistant AI'),
        backgroundColor: (isDark ? const Color(0xFF0F172A) : Colors.white)
            .withValues(alpha: 0.7),
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                : [const Color(0xFFF8FAFC), const Color(0xFFE2E8F0)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 24,
                  ),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    final isUser = message['role'] == 'user';
                    return Align(
                      alignment: isUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        decoration: BoxDecoration(
                          color: isUser
                              ? (isDark
                                    ? const Color(0xFF3B82F6)
                                    : const Color(0xFF2563EB))
                              : (isDark
                                    ? const Color(0xFF1E293B)
                                    : Colors.white),
                          border: isUser
                              ? null
                              : Border.all(
                                  color: isDark
                                      ? const Color(0xFF334155)
                                      : const Color(0xFFE2E8F0),
                                ),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(20),
                            topRight: const Radius.circular(20),
                            bottomLeft: Radius.circular(isUser ? 20 : 4),
                            bottomRight: Radius.circular(isUser ? 4 : 20),
                          ),
                          boxShadow: [
                            if (!isUser)
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                          ],
                        ),
                        child: Text(
                          message['text'] ?? '',
                          style: TextStyle(
                            color: isUser
                                ? Colors.white
                                : (isDark
                                      ? Colors.white
                                      : const Color(0xFF1E293B)),
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_isLoading)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        "AI is typing...",
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.all(16.0).copyWith(bottom: 24),
                    decoration: BoxDecoration(
                      color: (isDark ? const Color(0xFF1E293B) : Colors.white)
                          .withValues(alpha: 0.6),
                      border: Border(
                        top: BorderSide(
                          color: Colors.white.withValues(
                            alpha: isDark ? 0.1 : 0.4,
                          ),
                          width: 1.5,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            decoration: InputDecoration(
                              hintText: 'Ask about safety procedures...',
                              hintStyle: TextStyle(
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                              filled: true,
                              fillColor: (isDark ? Colors.black : Colors.white)
                                  .withValues(alpha: 0.3),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 16,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF3B82F6).withValues(alpha: 0.8)
                                : const Color(
                                    0xFF2563EB,
                                  ).withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (isDark
                                            ? const Color(0xFF3B82F6)
                                            : const Color(0xFF2563EB))
                                        .withValues(alpha: 0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.send_rounded),
                            color: Colors.white,
                            onPressed: _sendMessage,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
