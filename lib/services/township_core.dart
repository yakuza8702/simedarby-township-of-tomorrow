/// Bridge to the Go native core (`go/townshipcore`, gomobile .aar) via a
/// MethodChannel hosted in MainActivity.kt. All embeddings cross as
/// little-endian float32 bytes because gomobile bind has no []float32.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

class KnnMatch {
  final String label;
  final double score; // cosine similarity
  const KnnMatch(this.label, this.score);

  static List<KnnMatch> parseJson(String raw) {
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return [for (final m in list) KnnMatch(m['label'] as String, (m['score'] as num).toDouble())];
  }
}

class VerifyReport {
  final String status; // ACCEPT_PLACEHOLDER | REJECT_*
  final String action;
  final int points;
  final int distance;
  final String reason;
  final String engine;
  VerifyReport(this.status, this.action, this.points, this.distance, this.reason, this.engine);

  bool get accepted => status == 'ACCEPT_PLACEHOLDER';

  static VerifyReport fromJson(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return VerifyReport(
      m['status'] as String,
      m['action'] as String? ?? '',
      (m['points'] ?? 0) as int,
      (m['distance'] ?? 0) as int,
      m['reason'] as String? ?? '',
      m['engine'] as String? ?? '',
    );
  }
}

class TownshipCore {
  static const _channel = MethodChannel('township/core');

  /// float32 vector -> little-endian bytes (gomobile has no []float32).
  static Uint8List f32Bytes(Float32List v) {
    final b = ByteData(v.length * 4);
    for (var i = 0; i < v.length; i++) {
      b.setFloat32(i * 4, v[i], Endian.little);
    }
    return b.buffer.asUint8List();
  }

  /// One-shot: the path passed via `am start -e twp_debug_import ...`, or null.
  static Future<String?> consumeDebugImport() async =>
      await _channel.invokeMethod<String>('consumeDebugImport');

  static Future<String> version() async =>
      await _channel.invokeMethod<String>('coreVersion') ?? 'unknown';

  /// kNN search over packed reference embeddings. [labelsLines] is
  /// "\n"-joined, one label per reference row.
  static Future<List<KnnMatch>> knnSearch(
      Float32List vec, Float32List db, List<String> labels, int k) async {
    final raw = await _channel.invokeMethod<String>('knnSearch', {
      'vec': f32Bytes(vec),
      'db': f32Bytes(db),
      'labels': labels.join('\n'),
      'k': k,
    });
    return KnnMatch.parseJson(raw ?? '[]');
  }

  static Future<String> pHashFile(String path) async =>
      await _channel.invokeMethod<String>('pHashFileDownscale', {'path': path}) ?? '';

  static Future<String> pHashBytes(Uint8List bytes) async =>
      await _channel.invokeMethod<String>('pHash', {'bytes': bytes}) ?? '';

  /// Placeholder anti-exploit gate for collection actions.
  static Future<VerifyReport> verifyAction(
      String action, String entryHash, Uint8List proofPhoto) async {
    final raw = await _channel.invokeMethod<String>('verifyAction', {
      'action': action,
      'entryHash': entryHash,
      'proof': proofPhoto,
    });
    return VerifyReport.fromJson(raw ?? '{}');
  }
}
