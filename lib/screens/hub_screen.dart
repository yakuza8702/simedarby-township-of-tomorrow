/// Circular Hub — residents list working items instead of binning them
/// ("reuse is the highest-value outcome in the loop"). Port of HubScreen.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../store/township_store.dart';
import '../theme.dart';

class HubScreen extends StatelessWidget {
  final TownshipStore store;
  const HubScreen({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(children: [
              Icon(Icons.volunteer_activism, color: context.tBrand),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Circular Hub — pass it on instead',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'A working item beats a recycled one. List it, a neighbour '
                'reserves it, and nothing is collected.',
                style: TextStyle(fontSize: 12, color: context.tMuted)),
            ),
          ),
          Expanded(
            child: store.hubListings.isEmpty
                ? _EmptyHub(onAdd: () => _newListing(context))
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: store.availableListings.length,
                    itemBuilder: (context, i) =>
                        _ListingCard(listing: store.availableListings[i], store: store),
                  ),
            ),
        ]),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text('List an item'),
          onPressed: () => _newListing(context),
        ),
      ),
    );
  }

  Future<void> _newListing(BuildContext context) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    if (!context.mounted) return;
    final dest = await store.persistPhoto(picked.path);
    if (!context.mounted) return;
    final ctrl = TextEditingController();
    final titleCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('List on the Hub'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: titleCtrl,
            decoration: const InputDecoration(labelText: 'What is it?'),
          ),
          TextField(
            controller: ctrl,
            decoration: const InputDecoration(
                labelText: 'Condition / how to pick it up'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('List it')),
        ],
      ),
    );
    if (ok == true && titleCtrl.text.trim().isNotEmpty) {
      store.addHubListing(
        title: titleCtrl.text.trim(),
        description: ctrl.text.trim(),
        photoPath: dest,
      );
    }
  }
}

class _EmptyHub extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyHub({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.chair_alt, size: 64, color: context.tGhost),
        const SizedBox(height: 12),
        const Text('Nothing has been shared in this precinct yet'),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('List the first item'),
        ),
      ]),
    );
  }
}

class _ListingCard extends StatelessWidget {
  final HubListing listing;
  final TownshipStore store;
  const _ListingCard({required this.listing, required this.store});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: listing.photoPath.isEmpty
            ? const Icon(Icons.image_not_supported)
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(listing.photoPath),
                    width: 56, height: 56, fit: BoxFit.cover)),
        title: Text(listing.title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${listing.owner} · ${listing.precinct} · '
            '${listing.status}',
            style: const TextStyle(fontSize: 12)),
        trailing: FilledButton.tonal(
          onPressed: () => store.toggleHubReservation(listing.id),
          child: Text(listing.status == 'available' ? 'Reserve' : 'Release',
              style: const TextStyle(fontSize: 12)),
        ),
      ),
    );
  }
}
