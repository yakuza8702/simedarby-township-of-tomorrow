/// Onboarding: household name + precinct + PDPA consent → straight into the
/// app. The legacy flow, rebuilt natively.
library;

import 'package:flutter/material.dart';

import '../store/township_store.dart';
import '../theme.dart';

class OnboardingScreen extends StatefulWidget {
  final TownshipStore store;
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.store, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  String _precinct = TownshipStore.precincts.first;
  bool _consent = false;
  int _step = 0;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _step == 0 ? _welcome() : _details(),
        ),
      ),
    );
  }

  Widget _welcome() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Icon(Icons.recycling, size: 72, color: context.tBrand),
          const SizedBox(height: 16),
          Text('Township of Tomorrow',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text(
            'Point your camera at waste, get the right bin, and log what you '
            'actually did with it. Everything runs on this phone — no cloud, '
            'no uploads.',
            style: TextStyle(fontSize: 16, height: 1.4),
          ),
          const Spacer(),
          FilledButton(
            onPressed: () => setState(() => _step = 1),
            child: const Text('Get started'),
          ),
        ],
      );

  Widget _details() => ListView(children: [
        Text('Set up your household',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            labelText: 'Your Name',
            hintText: 'e.g. Tan Wei Ming',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _address,
          decoration: const InputDecoration(
            labelText: 'Your Address',
            hintText: 'e.g. Block 12, Jalan Anggerik 3, Precinct 2',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        // Editable precinct: suggests Precinct 1-5 but accepts any typed text.
        Autocomplete<String>(
          initialValue: TextEditingValue(text: _precinct),
          optionsBuilder: (v) => v.text.isEmpty
              ? TownshipStore.precincts
              : TownshipStore.precincts
                  .where((p) => p.toLowerCase().contains(v.text.toLowerCase())),
          onSelected: (v) => setState(() => _precinct = v),
          fieldViewBuilder: (context, controller, focusNode, onSubmit) => TextField(
            controller: controller,
            focusNode: focusNode,
            decoration: const InputDecoration(
              labelText: 'Your precinct',
              hintText: 'e.g. Precinct 1',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _precinct = v),
            onSubmitted: (v) => setState(() => _precinct = v),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            // Soft green callout — the frozen tint token, both themes.
            color: context.tTintGreen,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'PDPA notice: photos you scan stay on this device. Features that '
            'share with neighbours are marked before you use them, and you '
            'choose what leaves your phone.',
            style: TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          value: _consent,
          onChanged: (v) => setState(() => _consent = v ?? false),
          title: const Text('I understand and agree',
              style: TextStyle(fontSize: 14)),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: (_name.text.trim().isNotEmpty && _consent)
              ? () {
                  widget.store.completeOnboarding(
                    _name.text.trim(),
                    _address.text.trim(),
                    _precinct,
                  );
                  widget.onDone();
                }
              : null,
          child: const Text('Start scanning'),
        ),
      ]);
}
