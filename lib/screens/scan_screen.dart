/// Scan tab: value-first camera consent → live camera preview → tap-to-capture
/// → on-device analysis → result → "Add to collection?" Yes/No flow.
///
/// Every camera/analysis failure lands on a panel that still offers a way
/// forward (WO-05):
/// * first visit renders the consent explainer *before* any camera plugin call;
/// * a permission denial renders the denied-recovery board (settings / retry /
///   skip), any other camera failure the camera-needed gate with a
///   Home-equivalent escape;
/// * a cancelled gallery import falls back to the camera-off panel, so the
///   flow never dead-ends;
/// * an unreadable photo (null result or thrown error) renders the recoverable
///   "Could not read that photo" panel, and `_analysing` is always cleared in a
///   `finally`.
library;

import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../cat_dex/cat_catch_gate.dart';
import '../cat_dex/cat_dex_store.dart';
import '../cat_dex/sticker_cutter.dart';
import '../services/local_llm.dart';
import '../services/scan_advisor.dart';
import '../services/scan_quips.dart';
import '../services/vision_pipeline.dart';
import '../services/waste_classifier.dart';
import '../main.dart';
import '../store/collection_store.dart';
import '../theme.dart';
import '../types.dart';

class ScanScreen extends StatefulWidget {
  final VisionPipeline pipeline;
  final CollectionStore store;
  const ScanScreen({super.key, required this.pipeline, required this.store});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

/// The hazard-report category vocabulary the report form offers — mirrors
/// `ReportScreen._categories` (private to the form, so the values are
/// re-stated here and every emitted value is checked against this set).
const _reportCategories = <String>{
  'Illegal dumping',
  'Bin overflowing',
  'Broken bin',
  'Street light out',
  'Fallen tree / branch',
  'Damaged street furniture',
  'Water pooling',
  'Other',
};

/// Map the raw detector / ML-Kit label behind a "Report this broken
/// structure" hand-off onto the report form's category vocabulary
/// (`ReportScreen.initialCategory`).
///
/// Conservative one-to-one subject matches only — a traffic light is a
/// street light outage, street-furniture hardware is damaged street
/// furniture, and a container-ish item reads as an overflowing bin. Every
/// OTHER label returns `null`, so the form preselects no category chip:
/// an out-of-vocabulary value would leave the resident staring at a form
/// whose selected chip does not exist.
String? reportCategoryForScanLabel(String? raw) {
  final label = raw?.trim().toLowerCase() ?? '';
  if (label.isEmpty) return null;
  const byLabel = <String, String>{
    'traffic light': 'Street light out',
    'stop sign': 'Damaged street furniture',
    'street sign': 'Damaged street furniture',
    'parking meter': 'Damaged street furniture',
    'fire hydrant': 'Damaged street furniture',
    'bench': 'Damaged street furniture',
    'bottle': 'Bin overflowing',
    'cup': 'Bin overflowing',
  };
  final mapped = byLabel[label];
  if (mapped != null) return mapped;
  // A label that already spells a form category passes through verbatim.
  for (final category in _reportCategories) {
    if (category.toLowerCase() == label) return category;
  }
  return null;
}

/// What the scan tab is showing.
///
/// Every fresh state starts at [_Phase.explainer]: the consent board renders
/// before any camera plugin call — value-first consent, reason first, the
/// system permission prompt only after the resident taps "Allow camera".
enum _Phase {
  /// Board-35 — the explainer ("Before the camera opens"). No plugin call yet.
  explainer,

  /// "Allow camera" pressed; the camera plugin is being initialised.
  starting,

  /// Live preview, ready to capture.
  ready,

  /// Camera deliberately off (import cancelled / declined): the resident can
  /// import a photo or switch the camera on. Never a dead end.
  off,

  /// Board-32 — the OS refused the camera permission; recovery is settings,
  /// retry or skip.
  denied,

  /// Board-07 — no camera at all / plugin unavailable; Home-equivalent escape.
  blocked,
}

class _ScanScreenState extends State<ScanScreen> {
  /// Set once the AI stack is ready; main.dart fires it for adb imports.
  static void Function(String)? externalImportHandler;

  /// The board-32 "Open settings" action — an app-settings intent on the
  /// Android side (`ACTION_APPLICATION_DETAILS_SETTINGS`), no new permission
  /// and no new dependency. Kept as a static const so tests can mock it.
  static const MethodChannel systemChannel = MethodChannel('township/system');

  CameraController? _controller;
  _Phase _phase = _Phase.explainer;
  bool _analysing = false;

  /// Set when the last analysis could not read the photo (null result, thrown
  /// error or failed capture). Replaces the base panel with the recoverable
  /// "Could not read that photo" board.
  bool _analysisFailed = false;
  ScanResult? _result;
  String? _lastPhotoPath;

  @override
  void initState() {
    super.initState();
    externalImportHandler = _analyseExternal;
    // Value-first consent: NO camera plugin call here. The first board the
    // resident sees is the explainer, and only "Allow camera" starts the
    // plugin flow.
    // adb debug-import (parked on App until a scan state exists).
    final pending = App.pendingDebugImport;
    if (pending != null && pending.isNotEmpty) {
      App.pendingDebugImport = null;
      Future.microtask(() => _analyseExternal(pending));
    }
  }

  /// A platform permission refusal — whatever plugin surfaced it. Codes come
  /// from the camera plugin (`CameraAccessDenied`, `CameraAccessRestricted`, …)
  /// or leak through as a raw [PlatformException]; both are matched here so the
  /// denied board, not the hard gate, is what the resident sees.
  static bool _isPermissionDenial(Object error) {
    final String code;
    final String description;
    if (error is CameraException) {
      code = error.code;
      description = error.description ?? '';
    } else if (error is PlatformException) {
      code = error.code;
      description = error.message ?? '';
    } else {
      return false;
    }
    final haystack = '${code.toLowerCase()} ${description.toLowerCase()}';
    return haystack.contains('denied') ||
        haystack.contains('permission') ||
        haystack.contains('restricted');
  }

  /// 'Allow camera' (and board-32 "Try again"): initialise the camera.
  ///
  /// Every failure is caught — [CameraException] (permission denial → the
  /// denied-recovery board, anything else → the camera-needed gate),
  /// [MissingPluginException] (headless / no plugin → the gate), an empty
  /// camera list (→ the gate) and anything else the platform throws. Nothing
  /// escapes as an unhandled exception.
  Future<void> _startCamera() async {
    if (!mounted) return;
    setState(() => _phase = _Phase.starting);
    CameraController? controller;
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        debugPrint('TWP:ERROR camera: no cameras available');
        // No devices at all → the hard gate (there is no permission to fix).
        await _cameraFailed(
            null, CameraException('NoCameras', 'no cameras available'));
        return;
      }
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cams.first);
      controller = CameraController(back, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _phase = _Phase.ready;
      });
    } on CameraException catch (e) {
      debugPrint('TWP:ERROR camera: ${e.code} ${e.description}');
      await _cameraFailed(controller, e);
    } on MissingPluginException catch (e) {
      // Headless test env / plugin never registered — the hard gate, not the
      // permission board (there was no OS prompt to refuse).
      debugPrint('TWP:ERROR camera plugin missing: $e');
      await _cameraFailed(controller, e);
    } catch (e) {
      debugPrint('TWP:ERROR camera: $e');
      await _cameraFailed(controller, e);
    }
  }

  /// Shared failure landing: dispose the half-built controller so a
  /// half-created platform session cannot leak, then route the error —
  /// permission refusal → board-32 denied recovery, anything else → board-07
  /// camera-needed gate.
  Future<void> _cameraFailed(CameraController? controller, Object error) async {
    try {
      await controller?.dispose();
    } catch (e) {
      debugPrint('TWP:ERROR camera dispose: $e');
    }
    if (!mounted) return;
    setState(() =>
        _phase = _isPermissionDenial(error) ? _Phase.denied : _Phase.blocked);
  }

  /// Board-32 "Open settings": hand the resident to this app's own system
  /// settings page. Failures are logged, never surfaced as a crash.
  Future<void> _openSettings() async {
    try {
      await systemChannel.invokeMethod('openAppSettings');
    } catch (e) {
      debugPrint('TWP:ERROR openAppSettings: $e');
    }
  }

  /// Board-07's Home-equivalent escape from the hard gate: as a pushed route
  /// this pops back to the home shell; inside the tab shell there is nothing
  /// to pop, so it falls back to the camera-off panel instead of leaving the
  /// resident stranded.
  void _goHome() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.popUntil((route) => route.isFirst);
    } else if (mounted) {
      setState(() => _phase = _Phase.off);
    }
  }

  /// Read [path] through the pipeline. A null result or a thrown error is a
  /// recoverable failure — the failure board — never a silent dead end.
  Future<void> _analysePath(String path) async {
    _lastPhotoPath = path;
    ScanResult? result;
    try {
      result = await widget.pipeline.analyseFile(path);
    } catch (e) {
      debugPrint('TWP:ERROR analyse: $e');
      result = null;
    }
    if (!mounted) return;
    setState(() {
      _result = result;
      _analysisFailed = result == null;
    });
  }

  /// adb debug-import entry point (main.dart / [ScanScreenStateProxy]).
  Future<void> _analyseExternal(String path) async {
    if (!mounted || _analysing) return;
    setState(() => _analysing = true);
    try {
      await _analysePath(path);
    } finally {
      if (mounted) setState(() => _analysing = false);
    }
  }

  Future<void> _capture() async {
    if (_analysing) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() => _analysing = true);
    try {
      final file = await controller.takePicture();
      await _analysePath(file.path);
    } catch (e) {
      debugPrint('TWP:ERROR capture: $e');
      if (mounted) setState(() => _analysisFailed = true);
    } finally {
      if (mounted) setState(() => _analysing = false);
    }
  }

  /// Import from the gallery — also the deterministic path used by the
  /// emulator compatibility tests, the explainer's "Not now" and board-32's
  /// "Skip for now".
  ///
  /// Cancelling the picker returns to the camera-off panel ("Import a photo" /
  /// "Allow camera") unless the preview is already live, so no entry path can
  /// dead-end.
  Future<void> _import() async {
    if (_analysing) return;
    setState(() => _analysing = true);
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) {
        if (mounted) {
          setState(() {
            _analysisFailed = false;
            if (_phase != _Phase.ready) _phase = _Phase.off;
          });
        }
        return;
      }
      await _analysePath(picked.path);
    } catch (e) {
      debugPrint('TWP:ERROR import: $e');
      if (mounted) setState(() => _analysisFailed = true);
    } finally {
      if (mounted) setState(() => _analysing = false);
    }
  }

  void _backToCamera() => setState(() {
        _result = null;
        _analysisFailed = false;
      });

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_result != null) {
      return _ResultView(
        result: _result!,
        photoPath: _lastPhotoPath!,
        pipeline: widget.pipeline,
        store: widget.store,
        onRescan: _backToCamera,
      );
    }
    if (_analysisFailed) {
      return _AnalysisFailurePanel(
        onTryAnother: () => setState(() => _analysisFailed = false),
        onImport: _import,
      );
    }
    final base = _buildBase();
    if (_analysing) {
      return Stack(
        fit: StackFit.expand,
        children: [base, const _AnalysingOverlay()],
      );
    }
    return base;
  }

  /// The panel for the current phase (never the analysing overlay — [build]
  /// layers that on top).
  Widget _buildBase() {
    switch (_phase) {
      case _Phase.explainer:
        return _CameraConsentExplainer(onAllow: _startCamera, onNotNow: _import);
      case _Phase.starting:
        return const _StartingCamera();
      case _Phase.ready:
        final controller = _controller;
        if (controller == null || !controller.value.isInitialized) {
          return const _StartingCamera();
        }
        return _buildPreview(controller);
      case _Phase.off:
        return _CameraOffPanel(onImport: _import, onAllow: _startCamera);
      case _Phase.denied:
        return _PermissionDeniedPanel(
          onOpenSettings: _openSettings,
          onRetry: _startCamera,
          onSkip: _import,
        );
      case _Phase.blocked:
        return _PermissionGate(onHome: _goHome, onRetry: _startCamera);
    }
  }

  /// Live preview + the capture/import controls (existing flow).
  Widget _buildPreview(CameraController controller) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(controller),
        Positioned(
          left: 0, right: 0, bottom: 24,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _RoundAction(
                icon: Icons.photo_library_outlined,
                label: 'Import',
                onTap: _import,
              ),
              const SizedBox(width: 28),
              Semantics(
                button: true,
                label: 'Take photo',
                child: GestureDetector(
                  onTap: _analysing ? null : _capture,
                  child: Container(
                    width: 76, height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _analysing ? Colors.white24 : Colors.white,
                      border: Border.all(color: const Color(0xFF2E7D32), width: 4),
                    ),
                    child: _analysing
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.camera_alt, size: 38, color: Color(0xFF2E7D32)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The shared panel frame every board uses: safe area, scrollable (so nothing
/// overflows on a small phone or a 600-px test viewport), single-column and
/// centre-aligned.
class _BoardFrame extends StatelessWidget {
  final Widget child;
  const _BoardFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// One board action — always ≥44 dp tall (a11y target) and full width so the
/// thumb cannot miss it.
class _BoardButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final _BoardButtonKind kind;
  const _BoardButton(this.label, {required this.onPressed, required this.kind});

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(minimumSize: const Size(64, 48));
    final child = Text(label);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: switch (kind) {
        _BoardButtonKind.filled =>
          SizedBox(width: double.infinity, child: FilledButton(onPressed: onPressed, style: style, child: child)),
        _BoardButtonKind.tonal =>
          SizedBox(width: double.infinity, child: FilledButton.tonal(onPressed: onPressed, style: style, child: child)),
        _BoardButtonKind.outlined =>
          SizedBox(width: double.infinity, child: OutlinedButton(onPressed: onPressed, style: style, child: child)),
        _BoardButtonKind.text =>
          SizedBox(width: double.infinity, child: TextButton(onPressed: onPressed, style: style, child: child)),
      },
    );
  }
}

enum _BoardButtonKind { filled, tonal, outlined, text }

/// Board-35 — value-first camera consent. Rendered before *any* camera plugin
/// call: glyph, title, the one reason, three checks, then the choice.
class _CameraConsentExplainer extends StatelessWidget {
  final VoidCallback onAllow;
  final VoidCallback onNotNow;
  const _CameraConsentExplainer({required this.onAllow, required this.onNotNow});

  static const String title = 'Before the camera opens';
  static const String reason =
      'We ask once, with a reason: the scan runs on this device — nothing is uploaded.';
  static const List<String> checks = [
    'Runs on-device, no cloud',
    'Nothing is uploaded',
    'Revoke anytime in Settings',
  ];

  @override
  Widget build(BuildContext context) {
    return _BoardFrame(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: context.tTintGreen,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: context.tCard),
              child: SizedBox(
                width: 72, height: 72,
                child:
                    Icon(Icons.photo_camera, size: 36, color: context.tBrand),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              reason,
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 14, color: context.tMuted, height: 1.4),
            ),
            const SizedBox(height: 16),
            for (final check in checks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, size: 20, color: context.tBrand),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        check,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            _BoardButton('Allow camera', onPressed: onAllow, kind: _BoardButtonKind.filled),
            _BoardButton('Not now', onPressed: onNotNow, kind: _BoardButtonKind.text),
          ],
        ),
      ),
    );
  }
}

/// "Allow camera" pressed — the plugin is coming up. Reduced motion gets a
/// static glyph instead of the spinner.
class _StartingCamera extends StatelessWidget {
  const _StartingCamera();

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return _BoardFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (reduce)
            Icon(Icons.photo_camera, size: 48, color: context.tBrand)
          else
            CircularProgressIndicator(color: context.tBrand),
          const SizedBox(height: 16),
          Text('Starting the camera…',
              style: TextStyle(fontSize: 15, color: context.tMuted)),
        ],
      ),
    );
  }
}

/// The camera-off panel: where every cancelled/declined import lands, so the
/// flow always keeps both ways forward — import a photo, or turn the camera
/// on.
class _CameraOffPanel extends StatelessWidget {
  final VoidCallback onImport;
  final VoidCallback onAllow;
  const _CameraOffPanel({required this.onImport, required this.onAllow});

  static const String title = 'The camera is off';

  @override
  Widget build(BuildContext context) {
    return _BoardFrame(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: context.tTintBlue,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_camera_outlined, size: 52, color: context.tInfo),
            const SizedBox(height: 12),
            const Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Import a photo from your gallery, or allow the camera when '
              'you use the scanner — analysis stays on this device either way.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 14, color: context.tMuted, height: 1.4),
            ),
            const SizedBox(height: 16),
            _BoardButton('Import a photo', onPressed: onImport, kind: _BoardButtonKind.filled),
            _BoardButton('Allow camera', onPressed: onAllow, kind: _BoardButtonKind.outlined),
          ],
        ),
      ),
    );
  }
}

/// Board-32 — the OS denied the camera permission. Three ways out: system
/// settings, retry, or skip straight to the gallery import.
class _PermissionDeniedPanel extends StatelessWidget {
  final VoidCallback onOpenSettings;
  final VoidCallback onRetry;
  final VoidCallback onSkip;
  const _PermissionDeniedPanel({
    required this.onOpenSettings,
    required this.onRetry,
    required this.onSkip,
  });

  static const String title = 'Camera permission denied';
  static const String body =
      'No problem.\nThe scanner needs the camera only when you use it — your '
      'photos stay on this device and you can change this anytime in system settings.';

  @override
  Widget build(BuildContext context) {
    return _BoardFrame(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: context.tCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.tError, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_photography, size: 52, color: context.tError),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: context.tError),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 14, color: context.tMuted, height: 1.45),
            ),
            const SizedBox(height: 16),
            _BoardButton('Open settings', onPressed: onOpenSettings, kind: _BoardButtonKind.filled),
            _BoardButton('Try again', onPressed: onRetry, kind: _BoardButtonKind.tonal),
            _BoardButton('Skip for now', onPressed: onSkip, kind: _BoardButtonKind.text),
          ],
        ),
      ),
    );
  }
}

/// Board-07 — no camera / no plugin. The existing copy stays verbatim; the
/// actions are a Home-equivalent escape plus a retry.
class _PermissionGate extends StatelessWidget {
  final VoidCallback onHome;
  final VoidCallback onRetry;
  const _PermissionGate({required this.onHome, required this.onRetry});

  static const String title = 'Camera access needed';
  static const String reason =
      'The scanner photographs waste through your camera. '
      'Nothing leaves the phone — analysis is on-device.';

  @override
  Widget build(BuildContext context) {
    return _BoardFrame(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: context.tTintBlue,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_camera_back, size: 64, color: context.tBrand),
            const SizedBox(height: 16),
            const Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              reason,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.tMuted, height: 1.4),
            ),
            const SizedBox(height: 20),
            _BoardButton('Home', onPressed: onHome, kind: _BoardButtonKind.filled),
            _BoardButton('Try again', onPressed: onRetry, kind: _BoardButtonKind.tonal),
          ],
        ),
      ),
    );
  }
}

/// Recoverable analysis failure: null result, thrown error or unreadable
/// photo. Both actions fetch another photo, so the resident is never stuck.
class _AnalysisFailurePanel extends StatelessWidget {
  final VoidCallback onTryAnother;
  final VoidCallback onImport;
  const _AnalysisFailurePanel({required this.onTryAnother, required this.onImport});

  static const String title = 'Could not read that photo';

  @override
  Widget build(BuildContext context) {
    return _BoardFrame(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: context.tCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.tError, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image, size: 52, color: context.tError),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: context.tError),
            ),
            const SizedBox(height: 8),
            Text(
              'The photo could not be read on this device, so nothing was '
              'analysed and nothing was uploaded. Try another photo or import '
              'one from your gallery.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 14, color: context.tMuted, height: 1.4),
            ),
            const SizedBox(height: 16),
            _BoardButton('Try another photo', onPressed: onTryAnother, kind: _BoardButtonKind.filled),
            _BoardButton('Import a photo', onPressed: onImport, kind: _BoardButtonKind.outlined),
          ],
        ),
      ),
    );
  }
}

/// Full-screen analysis overlay. Reduced motion (a11y) swaps the spinner for a
/// static glyph; the copy stays the same.
class _AnalysingOverlay extends StatelessWidget {
  const _AnalysingOverlay();

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Container(
      color: Colors.black.withValues(alpha: 0.55),
      child: Center(
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (reduce)
                const Icon(Icons.hourglass_top, size: 36, color: Colors.white)
              else
                const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 16),
              const Text('Working on-device…',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
              const SizedBox(height: 6),
              const Text('EfficientDet + kNN · runs without internet',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _RoundAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black38),
          child: IconButton(
            icon: Icon(icon, color: Colors.white),
            tooltip: label,
            style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
            onPressed: onTap,
          ),
        ),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
      ],
    );
  }
}

class _ResultView extends StatelessWidget {
  final ScanResult result;
  final String photoPath;
  final VisionPipeline pipeline;
  final CollectionStore store;
  final VoidCallback onRescan;

  const _ResultView({
    required this.result,
    required this.photoPath,
    required this.pipeline,
    required this.store,
    required this.onRescan,
  });

  /// Title + quip for the headline slot: the primary detected box when the
  /// detector found one, otherwise the same evidence order the guidance card
  /// uses (kNN identity → strongest ML Kit label → what the stream matched on).
  ///
  /// Waste-relevance comes off the box (`DetectedObject.wasteRelevant` — the
  /// value the chip row already renders as "not-a-waste-item"); with no box
  /// there is no such flag, so a decided stream stands in for it.
  ///
  /// `catDistributionCopy: false` because the Dex catch is gated on
  /// [CatDistributionCard.catchableCatBox]: a non-cat animal (or a suppressed
  /// cat) must not be told the Cat Distribution System noted its sighting.
  ({String title, String quip}) _quips() {
    final top = _primaryObject();
    return ScanQuips.forResult(
      topLabel: top?.label ?? ScanAdvisor.fromScanResult(result).label,
      category: top?.category.name ?? result.outcome.category?.name ?? '',
      isWasteRelevant: top?.wasteRelevant ?? result.outcome.category != null,
      catDistributionCopy: false,
    );
  }

  /// The first labelled box. The pipeline sorts waste evidence first and
  /// strongest first, so the head of the list is the box the resident cares
  /// about — the same rule [ScanAdvisor] applies.
  DetectedObject? _primaryObject() {
    for (final object in result.objects) {
      if (object.wasteRelevant && object.label.isNotEmpty) return object;
    }
    for (final object in result.objects) {
      if (object.label.isNotEmpty) return object;
    }
    return null;
  }

  /// No nested [Scaffold] here — this view is always mounted by the route or
  /// the tab shell's own Scaffold, which stays the only one (SafeArea + the
  /// ListView's bottom padding do the rest).
  @override
  Widget build(BuildContext context) {
    final o = result.outcome;
    final guidance = o.category == null ? null : GUIDANCE[o.category!];
    final quips = _quips();
    final theme = Theme.of(context);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(File(photoPath),
                height: 240, fit: BoxFit.cover),
          ),
          const SizedBox(height: 16),
          Card(
            color: o.category == null
                ? context.tAmberWashWarm
                : context.tTintGreen,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (o.category != null) ...[
                  Text(quips.title,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(quips.quip, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text('Category: ${o.category!.display}',
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text('Confidence ${o.confidence}% · ${result.totalMs} ms · on-device',
                      style: theme.textTheme.bodySmall),
                ] else ...[
                  Text(quips.title,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(quips.quip, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text(
                    'The scanner is not sure enough to assert. Best guesses: '
                    '${o.candidates.take(3).map((c) => c.display).join(', ')}',
                    style: theme.textTheme.bodyMedium),
                ],
                if (o.knnItem.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Looks like: ${o.knnItem} '
                        '(local embedding kNN${result.knn != null ? ' · ${result.knn!.cosine.toStringAsFixed(2)}' : ''})',
                        style: TextStyle(color: context.tBrand, fontSize: 13)),
                  ),
                if (o.matchedFrom != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Evidence: ${o.matchedFrom}',
                        style: theme.textTheme.bodySmall),
                  ),
              ]),
            ),
          ),
          if (result.objects.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _DetectedObjectChips(objects: result.objects),
              ),
            ),
          ],
          // Cat Distribution System: only when this photo really held a cat —
          // confident, and not outranked by another animal (the shared gate in
          // lib/cat_dex/cat_catch_gate.dart).
          if (CatDistributionCard.catchableCatBox(result.objects) != null) ...[
            const SizedBox(height: 12),
            CatDistributionCard(objects: result.objects, photoPath: photoPath),
          ],
          if (guidance != null) ...[
            const SizedBox(height: 12),
            Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.delete_outline, color: context.tSuccess),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(guidance.bin,
                      style: const TextStyle(fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 8),
                Text(guidance.action),
                const SizedBox(height: 8),
                Text(guidance.impact,
                    style: TextStyle(fontSize: 12, color: context.tMuted)),
              ]),
            )),
          ],
          const SizedBox(height: 12),
          // Bundled on-device language layer: headline, what to do, why it
          // matters, plus tappable follow-up questions.
          _OnDeviceGuidanceCard(result: result),
          const SizedBox(height: 16),
          // Confirm action → "Add to collection?" menu (spec flow).
          FilledButton.icon(
            icon: const Icon(Icons.playlist_add_check),
            label: const Text('Confirm action'),
            onPressed: () => _confirmDialog(context),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.report_problem),
            label: Text(o.infrastructure
                ? 'Report this broken structure'
                : 'Report a problem here'),
            onPressed: () => Navigator.pushNamed(
                context, '/report',
                // Raw COCO label -> the form's category vocabulary; anything
                // unmapped passes as null so no chip preselects.
                arguments:
                    o.infrastructure ? reportCategoryForScanLabel(o.matchedFrom) : null),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onRescan, child: const Text('Scan another')),
        ],
      ),
    );
  }

  Future<void> _confirmDialog(BuildContext context) async {
    final o = result.outcome;
    final category = o.category;
    // Even an unsure scan can be confirmed by the resident choosing a stream.
    WasteCategory? chosen = category;
    if (category == null) {
      final picked = await showDialog<WasteCategory>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Which stream is this?'),
          children: [
            for (final c in o.candidates)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, c),
                child: Text(c.display),
              ),
            for (final c in MANUAL_CATEGORIES.where((c) => !o.candidates.contains(c)))
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, c),
                child: Text(c.display, style: TextStyle(color: context.tFaint)),
              ),
          ],
        ),
      );
      if (picked == null) return;
      chosen = picked;
    }
    if (!context.mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add to collection?'),
        content: Text('Keep "${o.knnItem.isNotEmpty ? o.knnItem : chosen!.display}" '
            '(${chosen!.display}) in your collection so you can log the task '
            '(recycle / remove / dispose) once it is done?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
        ],
      ),
    );
    if (yes != true) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Discarded — nothing added')));
      }
      onRescan();
      return;
    }
    final persisted = await store.persistPhoto(photoPath);
    await store.add(
      itemLabel: o.knnItem.isNotEmpty ? o.knnItem : (o.matchedFrom ?? chosen!.display),
      category: chosen!,
      confidence: o.confidence,
      photoPath: persisted,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Added to collection — ${chosen.display}. '
            'Finish the task in the Collection tab to earn a point.')));
    onRescan();
  }
}

/// "On-device guidance" card: what the bundled language layer
/// ([LocalLlmService]) makes of this scan.
///
/// The first pass runs with no question. Tapping a follow-up chip re-queries
/// the same service with that question and updates the card in place. All of it
/// is local string work on the bundled knowledge table — no network, no model
/// download, and no state change to the rest of the result view.
class _OnDeviceGuidanceCard extends StatefulWidget {
  final ScanResult result;
  const _OnDeviceGuidanceCard({required this.result});

  @override
  State<_OnDeviceGuidanceCard> createState() => _OnDeviceGuidanceCardState();
}

class _OnDeviceGuidanceCardState extends State<_OnDeviceGuidanceCard> {
  ScanAdvice? _advice;
  String _question = '';

  @override
  void initState() {
    super.initState();
    _ask('');
  }

  /// Ask the guidance engine — with the resident's question when a chip was
  /// tapped, with '' for the first pass.
  Future<void> _ask(String question) async {
    final advice = await LocalLlmService.advise(
      ScanAdvisor.fromScanResult(widget.result, userQuestion: question),
    );
    if (!mounted) return;
    setState(() {
      _advice = advice;
      _question = question;
    });
  }

  @override
  Widget build(BuildContext context) {
    final advice = _advice;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.tips_and_updates_outlined, color: context.tSuccess),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('On-device guidance',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 10),
          if (advice == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(),
              ),
            )
          else ...[
            Text(advice.headline,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            if (_question.isNotEmpty) ...[
              Text('You asked: $_question',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: context.tFaint)),
              const SizedBox(height: 6),
            ],
            Text(advice.guidance, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: context.tScheme.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(advice.binAction,
                  style: TextStyle(
                      color: context.tScheme.onPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 10),
            Text(advice.impactNote,
                style: TextStyle(fontSize: 12, color: context.tMuted)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final question in advice.followUps)
                  ActionChip(
                    label: Text(question),
                    onPressed: () => _ask(question),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(advice.modelInfo,
                style: TextStyle(fontSize: 10, color: context.tFaint)),
          ],
        ]),
      ),
    );
  }
}

/// The detector's boxes as resident-facing chips.
///
/// The pipeline hands the objects over in evidence order (waste first); this
/// row is a confidence read-out instead, so it re-sorts and keeps the head of
/// the list only — [_maxChips] boxes is what fits on a phone screen without
/// pushing the confirm button below the fold.
class _DetectedObjectChips extends StatelessWidget {
  final List<DetectedObject> objects;
  const _DetectedObjectChips({required this.objects});

  static const _maxChips = 8;

  @override
  Widget build(BuildContext context) {
    final ranked = [...objects]
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Detected objects (${ranked.length})',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final obj in ranked.take(_maxChips)) _ObjectChip(object: obj),
          ],
        ),
      ],
    );
  }
}

/// One chip: label · destination pill · detector confidence. Boxes the label
/// table did not call waste are flagged, so a chair or a person is not read as
/// a stream the resident then has to act on.
class _ObjectChip extends StatelessWidget {
  final DetectedObject object;
  const _ObjectChip({required this.object});

  static const _pillText = TextStyle(
      fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white);

  /// recycle = green, reusable = blue, trash = gray (the collection streams).
  Color get _categoryColor => switch (object.category) {
        RecycleCategory.recycle => const Color(0xFF2E7D32),
        RecycleCategory.reusable => const Color(0xFF1565C0),
        RecycleCategory.trash => const Color(0xFF616161),
      };

  @override
  Widget build(BuildContext context) {
    final percent = (object.confidence * 100).round();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: context.tCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.tHairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(object.label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: _categoryColor,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(object.category.name, style: _pillText),
            ),
            const SizedBox(width: 6),
            Text('$percent%',
                style: TextStyle(fontSize: 12, color: context.tMuted)),
            if (!object.wasteRelevant) ...[
              const SizedBox(width: 6),
              Text('not-a-waste-item',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: context.tError)),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Cat Distribution System" card — the scan result view's cat path.
///
/// When any detected box is labelled `cat`, the result view offers the catch:
/// the analysed photo is re-read from its path, the strongest cat box is cut
/// into a sticker by [StickerCutter], the sighting is filed in the [CatDexStore]
/// and the app moves to `/cat-dex`. Every step is on-device — no network, no
/// upload, and a failure is a SnackBar rather than a crash.
///
/// The gate/scale arithmetic itself lives in
/// `lib/cat_dex/cat_catch_gate.dart` ([CatCatchGate]); the public statics below
/// stay as thin delegates so existing callers and tests keep working against
/// this class.
///
/// The three collaborators are injectable (`store` / `cutter` / `precinct`) so
/// widget tests can point at a temp dir instead of `path_provider`; the shipped
/// app leaves them null and the defaults resolve through [App.instance].
class CatDistributionCard extends StatelessWidget {
  /// The line the card leads with.
  static const String message =
      'A cat has appeared! The Cat Distribution System has assigned you a cat.';

  /// Call to action — also the string the tests tap.
  static const String buttonLabel = 'Catch it → Cat Dex';

  /// Shown when anything in the catch path throws.
  static const String escapeMessage = 'The cat slipped away — try another photo';

  /// Precinct used when the township store cannot be read.
  static const String fallbackPrecinct = 'Precinct A';

  /// The detector label that makes this card exist (COCO-80 `cat`) — delegate
  /// to the shared [CatCatchGate].
  static const String catLabel = CatCatchGate.catLabel;

  /// The default Dex item label when this scan held no other waste box.
  static const String strayCatLabel = 'stray cat';

  /// Every box of this scan, in the pipeline's evidence order.
  final List<DetectedObject> objects;

  /// The file the just-analysed photo was read from — its bytes are re-read on
  /// catch, so the sticker is cut from the real capture.
  final String photoPath;

  /// Injectable: null → `App.instance.catDex`.
  final CatDexStore? store;

  /// Injectable: null → `StickerCutter()` (app documents dir).
  final StickerCutter? cutter;

  /// Injectable: null → the township store's precinct, else [fallbackPrecinct].
  final String? precinct;

  const CatDistributionCard({
    super.key,
    required this.objects,
    required this.photoPath,
    this.store,
    this.cutter,
    this.precinct,
  });

  /// The highest-confidence box labelled [catLabel] — delegate to the shared
  /// [CatCatchGate] (the single definition lives in `cat_catch_gate.dart`).
  static DetectedObject? catBox(List<DetectedObject> objects) =>
      CatCatchGate.catBox(objects);

  /// The animals that compete with a cat for the sighting — the COCO-80 animal
  /// set the scan result copy already names.
  static const Set<String> animalLabels = CatCatchGate.competingAnimalLabels;

  /// Score floor a cat box must clear to offer the catch — delegate to
  /// [CatCatchGate.minCatConfidence] (the detector's own default, 0.25).
  static const double minCatConfidence = CatCatchGate.minCatConfidence;

  /// The cat box that may offer the dex catch (confident, and not outranked by
  /// another animal) — delegate to [CatCatchGate.catchableCatBox].
  static DetectedObject? catchableCatBox(List<DetectedObject> objects) =>
      CatCatchGate.catchableCatBox(objects);

  /// Map the pipeline's 640-px working-copy boxes back to full-resolution
  /// capture pixels — delegate to [CatCatchGate.scaleToOriginal].
  static double scaleToOriginal(int imageWidth, int imageHeight) =>
      CatCatchGate.scaleToOriginal(imageWidth, imageHeight);

  /// The human-facing item label filed with the catch: the strongest *non-cat
  /// waste* box this scan also saw (`bottle`, `can`, …) so the Dex entry names
  /// what the photo really held; a cat alone (or with only non-waste boxes)
  /// falls back to [strayCatLabel].
  static String itemLabelFor(List<DetectedObject> objects) {
    DetectedObject? best;
    for (final o in objects) {
      if (o.label.trim().toLowerCase() == catLabel) continue;
      if (!o.wasteRelevant || o.label.trim().isEmpty) continue;
      if (best == null || o.confidence > best.confidence) best = o;
    }
    return best == null ? strayCatLabel : best.label;
  }

  /// The precinct this assignment is filed under; never throws.
  String _precinct() {
    final injected = precinct;
    if (injected != null && injected.isNotEmpty) return injected;
    try {
      final fromStore = App.instance.township.precinct;
      return fromStore.isEmpty ? fallbackPrecinct : fromStore;
    } catch (e) {
      debugPrint('TWP:ERROR cat dex precinct: $e');
      return fallbackPrecinct;
    }
  }

  /// Cut the best cat box into a sticker, file it in the Dex, open the Dex.
  Future<void> _catch(BuildContext context) async {
    final box = catBox(objects);
    if (box == null) return;
    try {
      final bytes = await File(photoPath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      final scale = decoded == null
          ? 1.0
          : scaleToOriginal(decoded.width, decoded.height);
      final sighting = await (cutter ?? StickerCutter()).catchCat(
        imageBytes: bytes,
        boxX: box.x1 * scale,
        boxY: box.y1 * scale,
        boxW: box.width * scale,
        boxH: box.height * scale,
        label: catLabel,
        precinct: _precinct(),
        source: 'scan',
      );
      final dex = store ?? App.instance.catDex;
      await dex.addSighting(
        label: sighting.label,
        itemLabel: itemLabelFor(objects),
        precinct: sighting.precinct,
        source: sighting.source,
        originalPath: sighting.originalPath,
        stickerPath: sighting.stickerPath,
        capturedAt: sighting.capturedAt,
        id: sighting.id,
        name: sighting.name,
      );
      if (!context.mounted) return;
      Navigator.pushNamed(context, '/cat-dex');
    } catch (e) {
      debugPrint('TWP:ERROR cat catch: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(escapeMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final box = catBox(objects);
    // No cat in this scan → no card, no copy, no button.
    if (box == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Card(
      color: context.tAmberWashWarm,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.pets, color: context.tAmberIcon),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Cat Distribution System',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 8),
          const Text(message),
          const SizedBox(height: 4),
          Text('Cat detected at ${(box.confidence * 100).round()}% · '
              'the sticker stays on this device',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.pets),
            label: const Text(buttonLabel),
            onPressed: () => _catch(context),
          ),
        ]),
      ),
    );
  }
}

/// Current scan state's external-import handler (null when scan tab is dead).
void Function(String)? get scanStateHandler => _ScanScreenState.externalImportHandler;

/// Lets main.dart reach the scan state for the adb debug-import hook.
class ScanScreenStateProxy {
  static void fire(String path) {
    // The handler lives on the state; route through the static field.
    final handler = _ScanScreenState.externalImportHandler;
    if (handler != null) {
      handler(path);
    } else {
      debugPrint('TWP:ERROR no external import handler registered yet');
    }
  }
}
