import 'dart:html' as html;

// This file is ONLY compiled when Flutter detects the target is a Web Browser.

void injectWebMapsApiKeySafely(String apiKey) {
  final script = html.ScriptElement()
    ..src = 'https://maps.googleapis.com/maps/api/js?key=$apiKey'
    ..type = 'text/javascript';

  html.document.head?.append(script);
}
