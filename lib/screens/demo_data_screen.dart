/// Demo data screen: current dataset counts plus one-click load / reset.
///
/// A low-emphasis developer affordance pushed from Home — not part of the
/// resident flow. "Load demo data" is idempotent (each store is only filled
/// while empty); "Reset demo data" asks for confirmation, then clears every
/// demo collection, restores the board's synthetic seed and reseeds.
library;

import 'package:flutter/material.dart';

import '../services/demo_data.dart';
import '../theme.dart';

class DemoDataScreen extends StatefulWidget {
  /// Store override for tests; `null` → `DemoData()` (app singletons).
  final DemoData? demo;

  const DemoDataScreen({super.key, this.demo});

  @override
  State<DemoDataScreen> createState() => _DemoDataScreenState();
}

class _DemoDataScreenState extends State<DemoDataScreen> {
  DemoData? _fallback;

  DemoData get demo => widget.demo ?? (_fallback ??= DemoData());

  bool _busy = false;

  Future<void> _run(
    Future<DemoCounts> Function() action,
    String Function(DemoCounts) message,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final counts = await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message(counts))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run(
        demo.seed,
        (c) => 'Demo data ready — ${c.reports} reports, '
            '${c.collection} collection items, ${c.cats} cats.',
      );

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset demo data?'),
        content: const Text(
          'This clears demo reports, collection items, Cat Dex sightings '
          'and resets the community board. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.tScheme.error,
              foregroundColor: context.tScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset demo data'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      demo.reset,
      (_) => 'Demo data reset — the board is back to the synthetic seed.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final demo = this.demo;
    return Scaffold(
      appBar: AppBar(title: const Text('Demo data')),
      body: AnimatedBuilder(
        animation: Listenable.merge(
          [demo.township, demo.collection, demo.catDex, demo.board],
        ),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _countsCard(context, demo),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _load,
              style: FilledButton.styleFrom(
                backgroundColor: context.tScheme.primary,
                minimumSize: Size.fromHeight(kMinButtonSize),
              ),
              child: const Text('Load demo data'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _busy ? null : _reset,
              style: OutlinedButton.styleFrom(
                foregroundColor: context.tError,
                side: BorderSide(color: context.tError),
                minimumSize: Size.fromHeight(kMinButtonSize),
              ),
              child: const Text('Reset demo data'),
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              Center(
                child: Semantics(
                  label: 'Working on demo data',
                  child: const CircularProgressIndicator(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _countsCard(BuildContext context, DemoData demo) {
    final township = demo.township;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Current counts',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            const SizedBox(height: 8),
            _row('Hazard reports',
                '${township.reports.length} (${township.openReports} open)'),
            _row('Circular Hub listings', '${township.hubListings.length}'),
            _row('Collection items', '${demo.collection.entries.length}'),
            _row('Cat Dex sightings', '${demo.catDex.count}'),
            _row('Board posts', '${demo.board.postCount}'),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ]),
      );
}
