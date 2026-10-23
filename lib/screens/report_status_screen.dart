/// Report status tracking: every hazard report the resident has sent, newest
/// first, with its queue timeline and — once operators mark it resolved — a
/// one-tap share of that resolution to the community board.
///
/// Status vocabulary: the UI always says Received / In review / Resolved; the
/// raw store codes (written by township_store, matched in the switch below)
/// never surface in copy.
/// Nothing here is colour-only: chips carry text labels and every timeline
/// step carries a text timestamp (or an honest placeholder).
library;

import 'package:flutter/material.dart';

import '../community_board/board_models.dart';
import '../community_board/board_store.dart';
import '../main.dart' show App;
import '../store/township_store.dart';
import '../theme.dart';

/// Resident-facing reference shown on the receipt, the status cards, the
/// community-board resolution note and the command-center drill-down:
/// `RP-` plus the FIRST six hex digits of a 32-bit FNV-1a hash of the report
/// id. The hash is stable for a given id and no longer collides whenever two
/// microsecond-stamped ids share their tail (the old `RP-` + last-4-chars
/// scheme collided across any two ids created within ~10ms of each other).
String reportRef(String id) {
  var h = 0x811c9dc5; // FNV-1a 32-bit offset basis.
  for (final unit in id.codeUnits) {
    h ^= unit;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return 'RP-${h.toRadixString(16).padLeft(8, '0').substring(0, 6).toUpperCase()}';
}

/// The one UI label for a persisted status value.
String reportStatusLabel(String status) => switch (status) {
      'triaged' => 'In review',
      'resolved' => 'Resolved',
      _ => 'Received',
    };

/// Status tracking screen. Constructible standalone: [store] (and optionally
/// [board]) are injected so tests never touch the app singleton.
class ReportStatusScreen extends StatefulWidget {
  final TownshipStore store;

  /// `null` → the app singleton, same pattern as the cat-dex share.
  final CommunityBoardStore? board;

  /// Report id to highlight (the "Track my report" entry point).
  final String? highlightId;

  const ReportStatusScreen({
    super.key,
    required this.store,
    this.board,
    this.highlightId,
  });

  @override
  State<ReportStatusScreen> createState() => _ReportStatusScreenState();
}

class _ReportStatusScreenState extends State<ReportStatusScreen> {
  CommunityBoardStore get _board => widget.board ?? App.instance.board;

  Future<void> _shareResolution(HazardReport r) async {
    final postId = 'report-${r.id}';
    final already = _board.byId(postId) != null;
    if (!already) {
      // addPost is idempotent by id, so a retry can never double-post.
      await _board.addPost(BoardPost(
        id: postId,
        title: 'Resolved: ${r.category} — ${r.precinct}',
        body: '${r.description}\n\nMarked resolved by Township Operations. '
            'Ref ${reportRef(r.id)}.',
        category: 'Facilities',
        precinct: r.precinct,
        authorLabel: 'Township Operations',
        createdAt: DateTime.now(),
        isSynthetic: false,
      ));
    }
    if (!mounted) return;
    if (already) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Already shared to the community board')));
    }
    Navigator.of(context).pushNamed('/board');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My reports')),
      body: AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final reports = widget.store.reports; // newest first
          if (reports.isEmpty) return _emptyState(context);
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: reports.length,
            itemBuilder: (context, i) => _reportCard(context, reports[i]),
          );
        },
      ),
    );
  }

  Widget _emptyState(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.markunread_outlined,
                  size: 48, color: context.tGhost),
              const SizedBox(height: 12),
              Text('No reports yet',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                'A report you send will show its status here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.tMuted),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    backgroundColor: context.tScheme.primary),
                icon: const Icon(Icons.report_problem_outlined),
                label: const Text('Report a problem'),
                onPressed: () => Navigator.of(context).pushNamed('/report'),
              ),
            ],
          ),
        ),
      );

  Widget _reportCard(BuildContext context, HazardReport r) {
    final highlighted = r.id == widget.highlightId;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 0,
      color: highlighted ? context.tTintGreen : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: highlighted ? context.tBrand : context.tHairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Ref ${reportRef(r.id)} · ${r.category}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                _statusChip(context, r.status),
              ],
            ),
            const SizedBox(height: 6),
            Text(r.description,
                style: const TextStyle(fontSize: 13, height: 1.35)),
            const SizedBox(height: 12),
            _timeline(r),
            if (r.status == 'resolved') ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      backgroundColor: context.tScheme.primary),
                  icon: const Icon(Icons.campaign_outlined, size: 18),
                  label: const Text('Share resolution to board'),
                  onPressed: () => _shareResolution(r),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Never colour-only: the label text is the status, the colour is decoration.
  Widget _statusChip(BuildContext context, String status) {
    final label = reportStatusLabel(status);
    final (background, foreground) = switch (status) {
      'triaged' => (context.tTintBlue, context.tInk),
      'resolved' => (context.tTintGreen, context.tBrand),
      // Amber surface + ink text: 4.5:1 contrast on #F9A825. The amber chip
      // is deliberately the same in both themes — the ink is what pairs.
      _ => (kWarnAmber, kOnAmber),
    };
    return Semantics(
      label: 'Status: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: TextStyle(
                color: foreground,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _timeline(HazardReport r) {
    final steps = [
      _TimelineStep('Received', _timestamp(r.createdAt), reached: true),
      _TimelineStep('In review',
          r.triagedAt == null ? 'In progress' : _timestamp(r.triagedAt!),
          reached: r.triagedAt != null),
      _TimelineStep('Resolved',
          r.resolvedAt == null ? 'Upcoming' : _timestamp(r.resolvedAt!),
          reached: r.resolvedAt != null),
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
                      steps[i].reached
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 16,
                      color: steps[i].reached ? context.tBrand : context.tGhost,
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
                      Text(steps[i].label,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: steps[i].reached
                                  ? context.tInk
                                  : context.tFaint)),
                      const SizedBox(width: 8),
                      Text(steps[i].detail,
                          style: TextStyle(
                              fontSize: 12,
                              color: steps[i].reached
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
          'Status changes appear here as operators update the queue.',
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
}

class _TimelineStep {
  final String label;
  final String detail;
  final bool reached;
  const _TimelineStep(this.label, this.detail, {required this.reached});
}
