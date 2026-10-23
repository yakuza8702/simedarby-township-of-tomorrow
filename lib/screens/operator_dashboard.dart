/// Operator dashboard — the township staff tier, REACHABLE from inside the
/// app (Profile → Township staff) and via route /operator.
///
/// The operator loop, end to end:
///  * stats scoped to the selected queue scope (My precinct by default),
///  * an open queue split from "Recently resolved" (resolved cards no longer
///    linger next to actionable work),
///  * actions that follow state: submitted → tonal Review, in-review → outlined
///    Mark resolved, resolved → status chip only,
///  * resolving posts exactly one community-board notice (idempotent by id),
///  * a computed collection plan line.
///
/// Stores are OPTIONAL INJECTIONS — the same pattern as [StaffGuard] in
/// main.dart and [ReportStatusScreen]: `null` falls back to [App.instance] so
/// production wires the singletons and widget tests pass TempDir-backed
/// stores without ever touching `path_provider`.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../community_board/board_models.dart';
import '../community_board/board_store.dart';
import '../main.dart' show App;
import '../store/collection_store.dart';
import '../store/township_store.dart';
import '../theme.dart';
import 'report_status_screen.dart' show reportStatusLabel;

// ── pure queue math (unit-testable without a widget tree) ────────────────────

/// Stat triple for the stat row.
///
/// [open] counts `submitted` ONLY — In review and Resolved are counted on
/// their own — so `open + triaged + resolved` equals the scope's report count
/// and an in-review report is never double-counted.
({int open, int triaged, int resolved}) operatorScopeStats(
    List<HazardReport> reports) {
  return (
    open: reports.where((r) => r.status == 'submitted').length,
    triaged: reports.where((r) => r.status == 'triaged').length,
    resolved: reports.where((r) => r.status == 'resolved').length,
  );
}

/// The queue scope: [precinct]'s reports (the default "My precinct" view) or,
/// with [allPrecincts], every precinct.
List<HazardReport> operatorScopeReports(
  List<HazardReport> all,
  String precinct, {
  required bool allPrecincts,
}) =>
    allPrecincts
        ? List<HazardReport>.of(all)
        : [for (final r in all) if (r.precinct == precinct) r];

/// The open queue: actionable reports only (submitted + in review). Resolved
/// reports belong to [operatorRecentlyResolved] so they no longer linger here.
List<HazardReport> operatorQueue(List<HazardReport> scope) =>
    [for (final r in scope) if (r.status != 'resolved') r];

/// "Recently resolved": newest `resolvedAt` first, capped at [limit] (5).
/// A null `resolvedAt` sorts as the oldest so it can never crowd out fresh
/// resolutions.
List<HazardReport> operatorRecentlyResolved(List<HazardReport> scope,
    {int limit = 5}) {
  final resolved = [for (final r in scope) if (r.status == 'resolved') r];
  resolved.sort((a, b) {
    final ar = a.resolvedAt;
    final br = b.resolvedAt;
    if (ar == null && br == null) return 0;
    if (ar == null) return 1;
    if (br == null) return -1;
    return br.compareTo(ar);
  });
  return resolved.take(limit).toList();
}

/// High-severity actionable reports → the plan card's "priority" count.
int operatorPriorityCount(List<HazardReport> queue) =>
    queue.where((r) => r.severity == 'high').length;

/// The plan card line: 8 min per high-severity site visit, 2 min per pending
/// resident collection task. Both zero → the no-route copy.
String operatorPlanSummary({required int priority, required int tasks}) {
  if (priority == 0 && tasks == 0) {
    return 'No route needed today — queue is clear.';
  }
  final est = priority * 8 + tasks * 2;
  return '$priority priority · $tasks resident tasks · est. $est min';
}

// ── dashboard ────────────────────────────────────────────────────────────────

class OperatorDashboard extends StatefulWidget {
  /// Store overrides for tests; `null` → the app singleton.
  final TownshipStore? store;

  /// `null` → [App.instance.collection] — drives the plan card's task count.
  final CollectionStore? collection;

  /// `null` → [App.instance.board] — receives the one resolution notice.
  final CommunityBoardStore? board;

  const OperatorDashboard({
    super.key,
    this.store,
    this.collection,
    this.board,
  });

  @override
  State<OperatorDashboard> createState() => _OperatorDashboardState();
}

class _OperatorDashboardState extends State<OperatorDashboard> {
  /// Queue scope: `false` = 'My precinct' (the default), `true` = 'All precincts'.
  bool _allPrecincts = false;

  TownshipStore get _store => widget.store ?? App.instance.township;
  CollectionStore get _collection =>
      widget.collection ?? App.instance.collection;
  CommunityBoardStore get _board => widget.board ?? App.instance.board;

  /// The label the queue copy speaks: the precinct itself, or the scope name.
  String get _scopeLabel => _allPrecincts ? 'All precincts' : _store.precinct;

  /// Resolve [r] and post EXACTLY one board notice. `CommunityBoardStore
  /// .addPost` is idempotent by post id (`report-` + the report id), so a
  /// double-tap or a retry after a crash can never double-post.
  Future<void> _resolve(HazardReport r) async {
    _store.resolveReport(r.id);
    await _board.addPost(BoardPost(
      id: 'report-${r.id}',
      title: 'Resolved: ${r.category} — ${r.precinct}',
      body: '${r.description}\n\nMarked resolved by Township Operations.',
      category: 'Facilities',
      precinct: r.precinct,
      authorLabel: 'Township Operations',
      createdAt: DateTime.now(),
      isSynthetic: false,
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Resolved — posted to the community board')));
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    // One AnimatedBuilder, both notifiers: stats/queue follow the store, the
    // plan card also follows pending collection tasks.
    return AnimatedBuilder(
      animation: Listenable.merge([store, _collection]),
      builder: (context, _) {
        final scope = operatorScopeReports(store.reports, store.precinct,
            allPrecincts: _allPrecincts);
        final stats = operatorScopeStats(scope);
        final queue = operatorQueue(scope);
        final resolved = operatorRecentlyResolved(scope);
        final priority = operatorPriorityCount(queue);
        final tasks = _collection.pending;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Operator dashboard — ${store.precinct}',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Operator desk · review reports and close the loop',
                style: TextStyle(color: context.tMuted, fontSize: 13)),
            const SizedBox(height: 16),
            _scopeControl(),
            const SizedBox(height: 8),
            Row(children: [
              _stat(context, 'open', '${stats.open}', 'Open', context.tError),
              _stat(context, 'triaged', '${stats.triaged}', 'In review',
                  context.tBrand),
              _stat(context, 'resolved', '${stats.resolved}', 'Resolved',
                  context.tSuccess),
            ]),
            const SizedBox(height: 20),
            Text('Assessment queue',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (queue.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                      child: Text('No reports in $_scopeLabel — queue is '
                          'clear.')),
                ),
              )
            else
              for (final r in queue) _reportCard(context, r),
            if (resolved.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Recently resolved',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (final r in resolved) _reportCard(context, r),
            ],
            const Divider(height: 32),
            Text('Today\'s collection plan',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _planCard(priority, tasks),
          ],
        );
      },
    );
  }

  /// 'My precinct' / 'All precincts' segmented control (defaults to My precinct).
  Widget _scopeControl() {
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('My precinct')),
          ButtonSegment(value: true, label: Text('All precincts')),
        ],
        selected: {_allPrecincts},
        onSelectionChanged: (s) => setState(() => _allPrecincts = s.first),
        showSelectedIcon: false,
        style: ButtonStyle(
          minimumSize:
              WidgetStateProperty.all(const Size(0, kMinButtonSize)),
        ),
      ),
    );
  }

  /// One stat tile: big value over its label, keyed so tests (and screen
  /// readers) can address 'Open' / 'In review' / 'Resolved' unambiguously.
  Widget _stat(
      BuildContext context, String id, String value, String label, Color color) {
    return Expanded(
      child: Card(
        key: ValueKey('operator-stat-$id'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Semantics(
            label: '$label: $value',
            child: Column(children: [
              Text(value,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold, color: color)),
              Text(label, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ),
      ),
    );
  }

  /// Plan card: computed from high-severity open reports + pending tasks.
  Widget _planCard(int priority, int tasks) {
    final summary = operatorPlanSummary(priority: priority, tasks: tasks);
    final routeNeeded = priority > 0 || tasks > 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (routeNeeded) ...[
            const Text('Route A — organics + recycling',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
          ],
          Text(summary,
              style: TextStyle(fontSize: 12, color: context.tMuted)),
        ]),
      ),
    );
  }

  Widget _reportCard(BuildContext context, HazardReport r) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Semantics(
          label: '${r.category}, ${r.precinct}, severity ${r.severity}, '
              'status ${reportStatusLabel(r.status)}',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _severityChip(r),
              const SizedBox(width: 8),
              Expanded(
                child: Text(r.category,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              if (r.status != 'submitted') ...[
                const SizedBox(width: 8),
                _statusChip(r.status),
              ],
            ]),
            const SizedBox(height: 6),
            if (r.description.isNotEmpty)
              Text(r.description, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            // Meta speaks the shared status vocabulary (Received / In review /
            // Resolved via reportStatusLabel), never the raw store value.
            Text('${r.precinct} · ${reportStatusLabel(r.status)} · '
                '${_ago(r.createdAt)}',
                style: TextStyle(fontSize: 11, color: context.tMuted)),
            if (r.photoPath != null && r.photoPath!.isNotEmpty) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(r.photoPath!),
                    height: 120, fit: BoxFit.cover),
              ),
            ],
            // Actions follow state; resolved cards carry the status chip only.
            if (r.status != 'resolved') ...[
              const SizedBox(height: 8),
              Row(children: [
                if (r.status == 'submitted')
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      backgroundColor: context.tTintGreen,
                      foregroundColor: context.tBrand,
                      minimumSize: const Size(0, kMinButtonSize),
                    ),
                    onPressed: () => _store.triageReport(r.id),
                    child: const Text('Review'),
                  ),
                if (r.status == 'triaged')
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, kMinButtonSize)),
                    onPressed: () => _resolve(r),
                    child: const Text('Mark resolved'),
                  ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  /// Severity chip: high #B71C1C/white, medium #F9A825/ink, low tint-green +
  /// seed — never colour-only, the label says the severity out loud. Every
  /// text/background pair clears the 4.5:1 small-text contrast floor
  /// (low: seed #2E7D32 on tint #E8F5E9 = 4.56:1; the old white-on-#388E3C
  /// was only 4.12:1).
  Widget _severityChip(HazardReport r) {
    final (background, foreground) = switch (r.severity) {
      // onPrimary flips with the theme (white in light, deep green in dark),
      // so the pair keeps clearing 4.5:1 on both sides.
      'high' => (context.tError, context.tScheme.onError),
      // Amber surface + ink text: 4.5:1 contrast on #F9A825 — the same chip
      // in both themes, the ink is what pairs with it.
      'medium' => (kWarnAmber, kOnAmber),
      _ => (context.tTintGreen, context.tBrand),
    };
    return Semantics(
      label: 'Severity: ${r.severity}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(kPillRadius),
        ),
        child: Text(r.severity,
            style: TextStyle(
                color: foreground,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  /// Status chip (in-review / resolved cards): tint-blue + ink for In review,
  /// tint-green + seed for Resolved — the same pairs the resident-facing
  /// status screen uses, all >= 4.5:1.
  Widget _statusChip(String status) {
    final label = switch (status) {
      'triaged' => 'In review',
      'resolved' => 'Resolved',
      _ => 'Submitted',
    };
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
          borderRadius: BorderRadius.circular(kPillRadius),
        ),
        child: Text(label,
            style: TextStyle(
                color: foreground,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}
