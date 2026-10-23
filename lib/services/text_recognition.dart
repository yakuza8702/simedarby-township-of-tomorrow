/// Printed-text recognition ("Read printed text" on the scan result) — the
/// legacy app's ML Kit OCR, now through the official Flutter plugin.
library;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class TextRecognitionService {
  TextRecognizer? _recognizer;

  /// Returns the recognised printed text, or '' when nothing is found.
  Future<String> readText(String path) async {
    _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final input = InputImage.fromFilePath(path);
      final result = await _recognizer!.processImage(input);
      return result.text.trim();
    } catch (e) {
      debugPrint('TWP:ERROR ocr: $e');
      return '';
    }
  }

  void dispose() => _recognizer?.close();
}
