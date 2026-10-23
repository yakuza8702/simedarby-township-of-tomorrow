/// Collection tab: the resident's committed items. Select an entry → choose
/// the update (recycle / remove / dispose) → a proof photo is taken → the Go
/// core runs the placeholder verification → +1 placeholder point.
///
/// Spec note: points are a placeholder economy and verification is a
/// placeholder gate (see collection_store.dart) until the backend lands.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../store/collection_store.dart';
import '../theme.dart';
import '../types.dart';
import 'proof_capture_screen.dart';

class CollectionScreen extends StatelessWidget {
  final CollectionStore store;
  const CollectionScreen({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final entries = store.entries;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(children: [
                Icon(Icons.stars, color: context.tBrand),
                const SizedBox(width: 8),
                Text('${store.points} points',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                Text('${store.pending} pending',
                    style: Theme.of(context).textTheme.bodyMedium),
                const Spacer(),
                _PlaceholderChip(),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Finish a task: pick an item, choose Recycle / Remove / Dispose, '
                  'then photograph the proof. A fresh photo is required — reusing '
                  'the entry photo is rejected.',
                  style: TextStyle(fontSize: 12, color: context.tMuted)),
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? const _EmptyCollection()
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: entries.length,
                      itemBuilder: (context, i) => _EntryCard(
                        entry: entries[i],
                        store: store,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Board-38 empty state: shown when nothing has been collected yet. The
/// points/pending header above stays visible so the economy reads as waiting,
/// not broken.
class _EmptyCollection extends StatelessWidget {
  const _EmptyCollection();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: context.tHairline),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.delete_sweep_outlined,
                    size: 44, color: context.tGhost),
                const SizedBox(height: 12),
                Text(
                  'Nothing collected yet',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Log your first item after a scan — your streak starts with '
                  'bin no. 1.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: context.tMuted),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    backgroundColor: context.tScheme.primary,
                  ),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Start scanning'),
                  onPressed: () => Navigator.of(context).pushNamed('/scan'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaceholderChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'These points are a stand-in for now — every task is checked '
          'on this device (an allowed action plus a fresh proof photo) until '
          'the backend lands.',
      child: Chip(
        avatar: const Icon(Icons.science_outlined, size: 16),
        label: const Text('Demo points', style: TextStyle(fontSize: 11)),
        backgroundColor: context.tAmberWash,
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final CollectionEntry entry;
  final CollectionStore store;
  const _EntryCard({required this.entry, required this.store});

  // 'done' rides the brand green; 'awaiting' keeps the frozen warn amber —
  // both are legible on the card in either theme.
  Color _statusColor(BuildContext context) =>
      entry.status == 'done' ? context.tBrand : kWarnAmber;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: entry.photoPath.isEmpty
              ? const Icon(Icons.image_not_supported)
              : Image.file(File(entry.photoPath),
                  width: 56, height: 56, fit: BoxFit.cover),
        ),
        title: Text(entry.itemLabel,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${entry.category.display} · ${entry.confidence}% · '
            '${entry.status == "done" ? "${entry.action} · ${entry.pointsAwarded} pt · verified" : "awaiting task"}',
            style: const TextStyle(fontSize: 12)),
        trailing: Icon(
          entry.status == 'done' ? Icons.check_circle : Icons.arrow_forward_ios,
          color: _statusColor(context),
          size: entry.status == 'done' ? 24 : 16,
        ),
        onTap: () => _openActions(context),
      ),
    );
  }

  Future<void> _openActions(BuildContext context) async {
    final already = entry.status == 'done';
    final action = already
        ? null
        : await showModalBottomSheet<String>(
            context: context,
            builder: (ctx) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('What did you do with it?',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                for (final a in CollectionStore.actions)
                  ListTile(
                    leading: Icon(_iconFor(a)),
                    title: Text(_titleFor(a)),
                    subtitle: Text(_hintFor(a)),
                    onTap: () => Navigator.pop(ctx, a),
                  ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.close),
                  title: const Text('Cancel'),
                  onTap: () => Navigator.pop(ctx),
                ),
              ]),
            ),
          );
    if (action == null) return;
    if (!context.mounted) return;
    // Proof photo capture → verification → point.
    final proofPath = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ProofCaptureScreen(
          title: 'Proof: ${_titleFor(action)}',
          hint: 'Photograph the completed task. The same photo as the entry '
              'will be rejected.',
        ),
      ),
    );
    if (proofPath == null) return;
    final (ok, reason) = await store.completeAction(entry, action, proofPath);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? context.tScheme.primary : context.tScheme.error,
      content: Text(
        ok ? 'Verified — +1 point. $reason' : 'Rejected: $reason',
        // onPrimary / onError keep the banner copy readable on both themes.
        style: TextStyle(
          color: ok ? context.tScheme.onPrimary : context.tScheme.onError,
        ),
      ),
    ));
  }

  static IconData _iconFor(String action) => switch (action) {
        'recycle' => Icons.recycling,
        'remove' => Icons.remove_circle_outline,
        _ => Icons.local_shipping_outlined,
      };

  static String _titleFor(String action) => switch (action) {
        'recycle' => 'Recycle',
        'remove' => 'Remove',
        _ => 'Dispose',
      };

  static String _hintFor(String action) => switch (action) {
        'recycle' => 'Left it loose and clean in the blue bin',
        'remove' => 'Took it out of circulation (drop-off / shared hub)',
        _ => 'Sent to general waste — logged for the township ledger',
      };
}
