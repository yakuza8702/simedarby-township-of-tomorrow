/// Hazard-report flow: category → photo → severity → description → submit
/// → on-device receipt. The receipt replaces the form in place (no
/// SnackBar + pop), and the AppBar's "My reports" action opens the status
/// tracker so the loop closes back to the community board.
///
/// Honest location: no fake GPS. The resident attaches their precinct; the
/// report is stored with `lat`/`lng` null and the UI says so.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../store/township_store.dart';
import '../theme.dart';
import 'report_status_screen.dart';

/// Design tokens come from the shared palette (theme.dart) so this screen
/// follows the active light/dark theme — see `TownshipPalette`.

class ReportScreen extends StatefulWidget {
  final TownshipStore store;
  final String? initialCategory; // pre-filled when infrastructure was scanned
  const ReportScreen({super.key, required this.store, this.initialCategory});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  static const _categories = [
    'Illegal dumping',
    'Bin overflowing',
    'Broken bin',
    'Street light out',
    'Fallen tree / branch',
    'Damaged street furniture',
    'Water pooling',
    'Other',
  ];

  final _desc = TextEditingController();
  String _category = _ReportScreenStateInit.first;
  String _severity = 'medium';
  String? _photoPath;
  bool _precinctAttached = false;

  /// Set on submit: the form is swapped for the receipt state (board-36).
  HazardReport? _receipt;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory ?? _categories.first;
  }

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  /// Trimmed description must be non-empty before the report can be sent.
  bool get _valid => _desc.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report a problem'),
        actions: [
          IconButton(
            tooltip: 'My reports',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ReportStatusScreen(store: widget.store),
              ),
            ),
          ),
        ],
      ),
      body: _receipt != null ? _receiptBody(context) : _formBody(context),
    );
  }

  // ── form ─────────────────────────────────────────────────────────────────

  Widget _formBody(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in _categories)
              ChoiceChip(
                label: Text(c),
                selected: _category == c,
                onSelected: (_) => setState(() => _category = c),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _desc,
          maxLines: 3,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'What is wrong there?',
            hintText: 'Anything the operator needs to know',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Text('Severity', style: Theme.of(context).textTheme.titleSmall),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'low', label: Text('Low')),
            ButtonSegment(value: 'medium', label: Text('Medium')),
            ButtonSegment(value: 'high', label: Text('High')),
          ],
          selected: {_severity},
          onSelectionChanged: (s) => setState(() => _severity = s.first),
        ),
        const SizedBox(height: 16),
        // Photo + precinct (no GPS: precinct only, said out loud).
        Row(children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: const Icon(Icons.photo_camera),
            label: Text(_photoPath == null ? 'Add photo' : 'Change photo'),
            onPressed: _pickPhoto,
          ),
          const SizedBox(width: 12),
          _precinctAttached
              ? Semantics(
                  label: 'Location: ${widget.store.precinct}',
                  child: Chip(
                    avatar: const Icon(Icons.place_outlined, size: 16),
                    label: Text('Location: ${widget.store.precinct}'),
                    backgroundColor: context.tTintGreen,
                    side: BorderSide(color: context.tBrand),
                  ),
                )
              : OutlinedButton.icon(
                  style:
                      OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  icon: const Icon(Icons.place_outlined),
                  label: const Text('Attach precinct'),
                  onPressed: () => setState(() => _precinctAttached = true),
                ),
        ]),
        const SizedBox(height: 8),
        Text(
          'No GPS permission is requested — operators receive your precinct, '
          'not a street address.',
          style: TextStyle(fontSize: 11, color: context.tMuted),
        ),
        if (_photoPath != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(File(_photoPath!), height: 160, fit: BoxFit.cover),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              backgroundColor: context.tScheme.primary),
          icon: const Icon(Icons.send),
          label: const Text('Submit report'),
          onPressed: _valid ? _submit : null,
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            _valid
                ? 'Stored on this phone and queued for the operators — the sync '
                    'backend is the next milestone.'
                : 'Describe the problem before submitting.',
            style: TextStyle(fontSize: 11, color: context.tMuted),
            textAlign: TextAlign.center),
        ),
      ],
    );
  }

  // ── receipt (board-36) ───────────────────────────────────────────────────

  Widget _receiptBody(BuildContext context) {
    final report = _receipt!;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Card(
          elevation: 0,
          // Receipt hero: radius 16 per the design tokens.
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: context.tHairline)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  label: 'Report submitted',
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                        color: context.tTintGreen, shape: BoxShape.circle),
                    child: Icon(
                        Icons.check_circle, color: context.tBrand, size: 40),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Report logged — this is your receipt',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text('Ref ${reportRef(report.id)}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.tMuted)),
                const SizedBox(height: 16),
                _receiptSteps(),
                const SizedBox(height: 12),
                Text('Status: Received — logged just now',
                    style: TextStyle(fontSize: 12, color: context.tInk)),
                const SizedBox(height: 16),
                Divider(height: 1, color: context.tHairline),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        backgroundColor: context.tScheme.primary),
                    onPressed: () => Navigator.of(context)
                        .popUntil((route) => route.isFirst),
                    child: const Text('Back to home'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 44)),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ReportStatusScreen(
                              store: widget.store,
                              highlightId: report.id,
                            ),
                          ),
                        ),
                        child: const Text('Track my report'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      style: TextButton.styleFrom(
                          minimumSize: const Size(0, 44)),
                      onPressed: _resetForm,
                      child: const Text('New report'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Horizontal Received → In review → Resolved steps; labels are the text,
  /// colour only reinforces (never carries meaning alone).
  Widget _receiptSteps() {
    Widget step(String label, {required bool done}) => Expanded(
          child: Column(
            children: [
              Icon(
                done ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 20,
                color: done ? context.tBrand : context.tGhost,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: done ? FontWeight.w700 : FontWeight.w500,
                    color: done ? context.tInk : context.tFaint),
              ),
            ],
          ),
        );

    Widget connector() => Expanded(
          child: Container(
              height: 2,
              color: context.tHairline,
              margin: const EdgeInsets.only(bottom: 20)),
        );

    return Semantics(
      container: true,
      label: 'Queue steps: Received, In review, Resolved. Currently Received.',
      child: Row(
        children: [
          step('Received', done: true),
          connector(),
          step('In review', done: false),
          connector(),
          step('Resolved', done: false),
        ],
      ),
    );
  }

  // ── actions ──────────────────────────────────────────────────────────────

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.camera);
    if (picked == null) return;
    final dest = await widget.store.persistPhoto(picked.path);
    setState(() => _photoPath = dest);
  }

  void _submit() {
    final report = widget.store.addReport(
      category: _category,
      description: _desc.text.trim(),
      photoPath: _photoPath,
      severity: _severity,
      // Honest location: precinct only — never a fabricated coordinate.
      lat: null,
      lng: null,
    );
    setState(() => _receipt = report);
  }

  void _resetForm() {
    setState(() {
      _receipt = null;
      _desc.clear();
      _category = widget.initialCategory ?? _categories.first;
      _severity = 'medium';
      _photoPath = null;
      _precinctAttached = false;
    });
  }
}

class _ReportScreenStateInit {
  static const first = 'Illegal dumping';
}
