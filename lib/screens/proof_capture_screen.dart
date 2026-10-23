/// Minimal camera screen used to photograph PROOF of a completed task.
/// Returns the photo path via Navigator.pop.
library;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

class ProofCaptureScreen extends StatefulWidget {
  final String title;
  final String hint;
  const ProofCaptureScreen({super.key, required this.title, required this.hint});

  @override
  State<ProofCaptureScreen> createState() => _ProofCaptureScreenState();
}

class _ProofCaptureScreenState extends State<ProofCaptureScreen> {
  CameraController? _controller;
  bool _ready = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) return;
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cams.first);
      final c = CameraController(back, ResolutionPreset.high, enableAudio: false);
      await c.initialize();
      if (!mounted) return;
      setState(() { _controller = c; _ready = true; });
    } on CameraException catch (e) {
      debugPrint('TWP:ERROR proof camera: ${e.code}');
    }
  }

  Future<void> _shoot() async {
    if (_busy) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    setState(() => _busy = true);
    final file = await c.takePicture();
    if (mounted) Navigator.pop(context, file.path);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(widget.hint,
              style: TextStyle(color: context.tMuted, fontSize: 13)),
        ),
        Expanded(
          child: _ready
              ? CameraPreview(_controller!)
              : const Center(child: CircularProgressIndicator()),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            OutlinedButton(
                onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            const SizedBox(width: 24),
            FilledButton.icon(
              onPressed: _ready && !_busy ? _shoot : null,
              icon: const Icon(Icons.photo_camera),
              label: const Text('Capture proof'),
            ),
          ]),
        ),
      ]),
    );
  }
}
