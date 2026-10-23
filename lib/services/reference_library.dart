/// Teach-the-scanner reference library.
///
/// Residents photograph an item, name it and pick the stream; the capture is
/// embedded and added to the local kNN reference set. On-device, no cloud —
/// the same mechanism the seed set uses, just resident-grown.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../types.dart';
import 'embedder.dart';
import '../store/township_store.dart';

class ReferenceLibrary {
  final Embedder embedder;
  final TownshipStore store;
  ReferenceLibrary(this.embedder, this.store);

  static const _fileName = 'taught_refs.json';

  /// Add a taught photo: embed it and extend the runtime reference set.
  ///
  /// [streamLabel] is the resident-facing chip word the taught list should
  /// display (`'Paper'`, `'Other'`); it rides along with the display record
  /// only. The runtime contract is unchanged: the kNN reference is keyed by
  /// [label] and the persisted classifier record keeps [WasteCategory.name]
  /// (Paper → `Recyclable`, Other → `Landfill`).
  Future<bool> teach({
    required String photoPath,
    required String label,
    required WasteCategory stream,
    String? streamLabel,
  }) async {
    final bytes = await File(photoPath).readAsBytes();
    final vec = embedder.embedImageBytes(bytes);
    if (vec == null) return false;

    // 1) runtime reference set (this session)
    embedder.addRuntimeRef(label, vec);

    // 2) persist the ref embedding so the next launch reloads it
    await _persistRef(label, stream, photoPath, vec);

    // 3) store record for the educator UI — displayed under the resident's
    //    own stream word ('Paper'/'Other'), falling back to the category's
    //    display name when no label was supplied.
    store.addTaughtRef(
      label: label,
      stream: streamLabel ?? stream.display,
      photoPath: photoPath,
    );
    return true;
  }

  /// Reload taught refs persisted by earlier sessions into the kNN set.
  Future<void> loadPersisted() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/$_fileName');
      if (!await f.exists()) return;
      final list = (jsonDecode(await f.readAsString()) as List);
      for (final e in list) {
        final m = Map<String, dynamic>.from(e as Map);
        final bytes = base64Decode(m['db'] as String);
        final vec = Float32List.view(bytes.buffer);
        embedder.addRuntimeRef(m['label'] as String, vec);
      }
      debugPrint('TWP:refs loaded ${list.length} taught references');
    } catch (e) {
      debugPrint('TWP:ERROR refs load: $e');
    }
  }

  Future<void> _persistRef(
      String label, WasteCategory stream, String photoPath, Float32List vec) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/$_fileName');
      final list = await f.exists()
          ? (jsonDecode(await f.readAsString()) as List)
          : [];
      final data = TownshipCoreShim.f32Bytes(vec);
      // also remember the stream so the classifier phrase table can use it —
      // always the WasteCategory.name form ('Recyclable' for Paper, 'Landfill'
      // for Other), never the resident-facing streamLabel.
      list.add({
        'label': label,
        'stream': stream.name,
        'photoPath': photoPath,
        'db': base64Encode(data),
      });
      await f.writeAsString(jsonEncode(list));
    } catch (e) {
      debugPrint('TWP:ERROR refs persist: $e');
    }
  }
}

/// Bytes helper kept separate to avoid a circular import with the core.
class TownshipCoreShim {
  static Uint8List f32Bytes(Float32List v) {
    final b = ByteData(v.length * 4);
    for (var i = 0; i < v.length; i++) {
      b.setFloat32(i * 4, v[i], Endian.little);
    }
    return b.buffer.asUint8List();
  }
}
