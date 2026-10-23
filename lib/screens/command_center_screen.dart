/// Municipal command center — the council-tier control room: a LIVE resident
/// scan mix computed from [CollectionStore] entries, the truthful on-device
/// vision parameters, tappable incident rows with a read-only drill-down
/// sheet, and a deterministic SitRep over live counts.
///
/// The legacy `streamMix` constructor argument is kept so existing call sites
/// keep compiling, but the UI never reads it — the mix is recomputed from
/// `category.display` on every rebuild, and the rebuild is driven by
/// `Listenable.merge([store, collection])`.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../main.dart' show App;
import '../store/collection_store.dart';
import '../store/township_store.dart';
import '../theme.dart';
import '../types.dart';
import 'operator_dashboard.dart' show operatorScopeStats;
import 'report_status_screen.dart' show reportRef, reportStatusLabel;

class CommandCenterScreen extends StatelessWidget {
  final TownshipStore store;

  /// Collection state feeding the live mix; `null` → the app singleton
  /// (same optional-parameter pattern as `StaffGuard` in main.dart).
  final CollectionStore? collection;

  /// Legacy boot-time mix. Retained for source compatibility only — the
  /// screen computes its own live mix and never reads this value.
  final Map<String, int> streamMix;

  const CommandCenterScreen({
    super.key,
    required this.store,
    this.collection,
    this.streamMix = const {},
  });

  CollectionStore get _collection => collection ?? App.instance.collection;

  /// Live scan mix: one count per [WasteCategory.display] name, emitted in
  /// enum order so the bars are deterministic across rebuilds.
  Map<String, int> _liveMix() {
    final counts = <String, int>{};
    for (final e in _collection.entries) {
      final k = e.category.display;
      counts[k] = (counts[k] ?? 0) + 1;
    }
    return {
      for (final c in WasteCategory.values)
        if (counts[c.display] != null) c.display: counts[c.display]!,
    };
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild through BOTH stores: incidents/SitRep from the township store,
    // scan mix from the collection store.
    return AnimatedBuilder(
      animation: Listenable.merge([store, _collection]),
      builder: (context, _) {
        final mix = _liveMix();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Command center',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Command center · township-wide view',
                style: TextStyle(color: context.tMuted, fontSize: 13)),
            const SizedBox(height: 16),
            _streamMixCard(context, mix),
            const SizedBox(height: 18),
            _visionModelCard(context),
            const SizedBox(height: 18),
            _incidentCard(context),
            const SizedBox(height: 18),
            _sitRep(context, mix),
          ],
        );
      },
    );
  }

  // ── live scan mix ────────────────────────────────────────────────────────

  Widget _streamMixCard(BuildContext context, Map<String, int> mix) {
    final total = mix.values.fold(0, (a, b) => a + b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Resident scan mix (last scans)',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          if (total == 0)
            Text('No confirmed scans yet',
                style: TextStyle(color: context.tMuted))
          else
            for (final e in mix.entries) ...[
              Row(children: [
                Text(e.key, style: const TextStyle(fontSize: 12)),
                const Spacer(),
                Text('${(e.value / total * 100).round()}%',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12)),
              ]),
              const SizedBox(height: 4),
              _mixBar(context, e.value / total),
              const SizedBox(height: 8),
            ],
        ]),
      ),
    );
  }

  /// A bar-style mix row: a value-proportional fill on a flat track (not a
  /// progress indicator — this is a composition bar, not a loading state).
  Widget _mixBar(BuildContext context, double fraction) {
    return LayoutBuilder(builder: (context, c) {
      final maxW = c.maxWidth;
      final w = maxW.isFinite
          ? (maxW * fraction).clamp(0.0, maxW).toDouble()
          : 0.0;
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: 6,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(color: context.tScrim),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: w,
                height: 6,
                child: ColoredBox(color: context.tBrand),
              ),
            ),
          ),
        ),
      );
    });
  }

  // ── on-device vision parameters (truthful) ───────────────────────────────

  Widget _visionModelCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('On-device vision parameters',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'Primary detector: YOLO, 640×640 snapshot over 80 everyday '
              'object types',
              style: TextStyle(fontSize: 13)),
          const Text(
              'Fallback detector: EfficientDet-Lite0 int8, 320×320 — only when '
              'YOLO returns no boxes',
              style: TextStyle(fontSize: 13)),
          const Text(
              'Identity bonus: MobileNet-v3 small embedder + resident-taught kNN',
              style: TextStyle(fontSize: 13)),
          const Text('Label fallback: ML Kit on-device image labelling',
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 4),
          Text('Everything runs on this device · even with airplane mode on',
              style: TextStyle(fontSize: 12, color: context.tMuted)),
        ]),
      ),
    );
  }

  // ── incidents: live count, tappable rows ─────────────────────────────────

  Widget _incidentCard(BuildContext context) {
    final open = store.reports.where((r) => r.status != 'resolved').take(4)
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Incidents (${store.openReports} open)',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (open.isEmpty)
            Text('Nothing open — clean week',
                style: TextStyle(color: context.tBrand, fontSize: 13))
          else
            for (var i = 0; i < open.length; i++) ...[
              _incidentRow(context, open[i]),
              if (i != open.length - 1)
                Divider(height: 6, color: context.tHairline),
            ],
        ]),
      ),
    );
  }

  Widget _incidentRow(BuildContext context, HazardReport r) {
    final statusLabel = reportStatusLabel(r.status);
    return Semantics(
      container: true,
      button: true,
      label: '${r.category}, ${r.precinct}, status $statusLabel',
      child: InkWell(
        onTap: () => _openIncident(context, r),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(children: [
              Icon(_severityIcon(r.severity),
                  size: 16, color: _severityColor(context, r.severity)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${r.category} — ${r.precinct}',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              _statusChip(context, r.status),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right, size: 18, color: context.tMuted),
            ]),
          ),
        ),
      ),
    );
  }

  /// Never colour-only: the chip always spells the status out.
  Widget _statusChip(BuildContext context, String status,
      {double fontSize = 12}) {
    final label = reportStatusLabel(status);
    final (background, foreground) = switch (status) {
      'triaged' => (context.tTintBlue, context.tTintInk),
      // Seed on tint-green = 4.56:1 (kSuccessDark on the same tint was 3.66:1);
      // the dark theme swaps in the lifted seed on the dark tint.
      'resolved' => (context.tTintGreen, context.tBrand),
      // Amber surface + ink text: 4.5:1 contrast on #F9A825.
      _ => (kWarnAmber, kOnAmber),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: foreground,
              fontSize: fontSize,
              fontWeight: FontWeight.w600)),
    );
  }

  IconData _severityIcon(String severity) => switch (severity) {
        'high' => Icons.priority_high,
        'medium' => Icons.error_outline,
        _ => Icons.info_outline,
      };

  Color _severityColor(BuildContext context, String severity) =>
      switch (severity) {
        'high' => context.tError,
        'medium' => kWarnAmber,
        _ => context.tSuccess,
      };

  /// Read-only drill-down: ref, category, severity, precinct, description,
  /// photo thumbnail and the Received / In review / Resolved timeline.
  void _openIncident(BuildContext context, HazardReport r) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => _IncidentSheet(report: r),
    );
  }

  // ── deterministic SitRep over LIVE values ────────────────────────────────

  Widget _sitRep(BuildContext context, Map<String, int> mix) {
    // Disjoint triple, same helper as the operator stat row: `open` counts
    // submitted ONLY, so in-review reports are never double-counted as open.
    final stats = operatorScopeStats(store.reports);
    final mixText = mix.isEmpty
        ? 'no scans'
        : mix.entries.map((e) => '${e.key} ${e.value}').join(', ');
    // Deterministic situation report (legacy wording, minus any cloud mention)
    final text =
        'Precinct status: waste stream mix — $mixText. '
        'Hazard queue: ${stats.open} open, ${stats.triaged} in review, '
        '${stats.resolved} resolved. '
        'Hub sharing active (${store.hubListings.length} listings). '
        'All decisions verified on device.';
    return Card(
      color: context.tTintBlue,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Situation report',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(fontSize: 13, height: 1.4)),
        ]),
      ),
    );
  }
}

// ── read-only incident drill-down sheet ────────────────────────────────────

class _IncidentSheet extends StatelessWidget {
  final HazardReport report;
  const _IncidentSheet({required this.report});

  @override
  Widget build(BuildContext context) {
    final r = report;
    return Container(
      decoration: BoxDecoration(
        color: context.tCanvas,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.tGhost,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Text('Ref ${reportRef(r.id)}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              _sheetStatusChip(context, r.status),
            ]),
            const SizedBox(height: 12),
            _kv(context, 'Category', r.category),
            _kv(context, 'Severity', _capitalise(r.severity)),
            _kv(context, 'Precinct', r.precinct),
            const SizedBox(height: 10),
            Text('Description',
                style: TextStyle(fontSize: 12, color: context.tMuted)),
            const SizedBox(height: 2),
            Text(r.description,
                style: TextStyle(fontSize: 13, height: 1.4, color: context.tInk)),
            const SizedBox(height: 12),
            _photo(context, r.photoPath),
            const SizedBox(height: 14),
            Divider(color: context.tHairline),
            const SizedBox(height: 10),
            _timeline(context, r),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44)),
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Close'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 96,
              child: Text(k,
                  style: TextStyle(fontSize: 13, color: context.tMuted))),
          Expanded(
              child: Text(v,
                  style: TextStyle(
                      fontSize: 13, color: context.tInk, height: 1.35))),
        ]),
      );

  Widget _sheetStatusChip(BuildContext context, String status) {
    final label = reportStatusLabel(status);
    final (background, foreground) = switch (status) {
      'triaged' => (context.tTintBlue, context.tTintInk),
      'resolved' => (context.tTintGreen, context.tBrand),
      _ => (kWarnAmber, kOnAmber),
    };
    return Semantics(
      label: 'Status: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                color: foreground,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  /// Photo thumbnail — a real file renders as a 64dp cover thumb, anything
  /// else is an honest, labelled empty state (read-only, no viewer).
  Widget _photo(BuildContext context, String? path) {
    final hasPhoto =
        path != null && path.isNotEmpty && File(path).existsSync();
    return Row(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 64,
          height: 64,
          child: hasPhoto
              ? Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => ColoredBox(
                      color: context.tScrim,
                      child: Icon(Icons.broken_image_outlined,
                          color: context.tMuted)),
                )
              : ColoredBox(
                  color: context.tScrim,
                  child: Icon(Icons.image_outlined, color: context.tMuted)),
        ),
      ),
      const SizedBox(width: 10),
      Text(
        hasPhoto ? 'Photo' : 'No photo attached',
        style: TextStyle(fontSize: 13, color: context.tMuted),
      ),
    ]);
  }

  Widget _timeline(BuildContext context, HazardReport r) {
    final steps = <(String, String, bool)>[
      ('Received', _timestamp(r.createdAt), true),
      ('In review',
          r.triagedAt == null ? 'In progress' : _timestamp(r.triagedAt!),
          r.triagedAt != null),
      ('Resolved',
          r.resolvedAt == null ? 'Upcoming' : _timestamp(r.resolvedAt!),
          r.resolvedAt != null),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Row(
            children: [
              SizedBox(
                width: 24,
                child: Column(
                  children: [
                    Icon(
                      steps[i].$3
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 16,
                      color: steps[i].$3 ? context.tBrand : context.tGhost,
                    ),
                    if (i != steps.length - 1)
                      Container(width: 2, height: 14, color: context.tHairline),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      Text(steps[i].$1,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: steps[i].$3
                                  ? context.tInk
                                  : context.tFaint)),
                      const SizedBox(width: 8),
                      Text(steps[i].$2,
                          style: TextStyle(
                              fontSize: 12,
                              color: steps[i].$3
                                  ? context.tMuted
                                  : context.tFaint)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 4),
        Text(
          'Read-only view — operators update the queue.',
          style: TextStyle(fontSize: 11, color: context.tMuted),
        ),
      ],
    );
  }

  /// `Today · <HH:MM>` for same-day events, `d MMM · HH:MM` otherwise.
  String _timestamp(DateTime t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return 'Today · $hh:$mm';
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${t.day} ${months[t.month - 1]} · $hh:$mm';
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
