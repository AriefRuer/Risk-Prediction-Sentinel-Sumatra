import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final geminiServiceProvider = Provider<GeminiService>((ref) {
  return GeminiService();
});

class GeminiService {
  late GenerativeModel _model;
  ChatSession? _chat;

  GeminiService() {
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null) {
      throw Exception('No GEMINI_API_KEY found in .env');
    }
    _model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: apiKey);
    _chat = _model.startChat();
  }

  Stream<String> sendMessageStream(String text) async* {
    if (_chat == null) {
      yield "Chat not initialized.";
      return;
    }

    try {
      final content = Content.text(text);
      final responseStream = _chat!.sendMessageStream(content);

      await for (final chunk in responseStream) {
        if (chunk.text != null) {
          yield chunk.text!;
        }
      }
    } catch (e) {
      yield "Error connecting to AI: $e";
    }
  }
}
