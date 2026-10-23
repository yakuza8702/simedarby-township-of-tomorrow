/// First-time tour — deterministic, local (the legacy version was rebuilt
/// from the cloud tour generator to exactly this). Four steps over the tabs.
library;

import 'package:flutter/material.dart';

import '../store/township_store.dart';
import '../theme.dart';

class TourOverlay extends StatefulWidget {
  final TownshipStore store;
  const TourOverlay({super.key, required this.store});

  static Future<void> maybeShow(BuildContext context, TownshipStore store) async {
    if (store.tourDone) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => TourOverlay(store: store),
    );
  }

  @override
  State<TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<TourOverlay> {
  int _page = 0;

  static const _steps = [
    (
      Icons.camera_alt,
      'Scan first',
      'Point your camera at the item in good light. The scanner answers from '
      'models on this phone — no cloud, no uploads.',
    ),
    (
      Icons.playlist_add_check,
      'Confirm, don\'t guess',
      'The scanner only asserts when it is sure. Otherwise it asks you to '
      'confirm the stream — one tap, and the answer gets logged.',
    ),
    (
      Icons.recycling,
      'Collect → finish the task',
      'Add confirmed items to your Collection. When the task is done — recycle, '
      'remove or dispose — photograph the proof to earn a point.',
    ),
    (
      Icons.volunteer_activism,
      'Share and report',
      'List working items on the Circular Hub instead of binning them, and '
      'report broken street furniture with a photo for the operators.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final (icon, title, body) = _steps[_page];
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                for (var i = 0; i < _steps.length; i++)
                  Container(
                    width: i == _page ? 20 : 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: i <= _page ? context.tBrand : context.tScrim,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Icon(icon, size: 56, color: context.tBrand),
            const SizedBox(height: 16),
            Text(title,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(body, style: const TextStyle(fontSize: 14, height: 1.4)),
            const SizedBox(height: 20),
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    widget.store.completeTour();
                    Navigator.pop(context);
                  },
                  child: const Text('Skip'),
                ),
                const Spacer(),
                if (_page < _steps.length - 1)
                  FilledButton(
                    onPressed: () => setState(() => _page++),
                    child: const Text('Next'),
                  )
                else
                  FilledButton(
                    onPressed: () {
                      widget.store.completeTour();
                      Navigator.pop(context);
                    },
                    child: const Text('Done'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
