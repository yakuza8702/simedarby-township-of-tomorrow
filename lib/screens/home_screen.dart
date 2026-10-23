/// Home: the township dashboard — status, quick actions, my impact. Ported
/// from the legacy HomeScreen (status chips + entry tiles, offline wording).
library;

import 'package:flutter/material.dart';

import 'demo_data_screen.dart';
import '../store/township_store.dart';
import '../theme.dart';

class HomeScreen extends StatelessWidget {
  final TownshipStore store;
  final CollectionStats stats;
  const HomeScreen({super.key, required this.store, required this.stats});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => AnimatedBuilder(
        animation: stats,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _statusCard(context),
            const SizedBox(height: 14),
            Row(children: [
              Text('Quick actions',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 10),
            _quickActions(context),
            const SizedBox(height: 18),
            Text('My impact this month',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _impact(context),
            // Low-emphasis developer affordance, deliberately below the
            // impact card and out of the quick-action grid.
            Center(
              child: TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 44),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const DemoDataScreen(),
                  ),
                ),
                child: Text(
                  'Demo data',
                  style: TextStyle(fontSize: 13, color: context.tFaint),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusCard(BuildContext context) {
    return Card(
      color: context.tTintGreen,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(Icons.offline_bolt, color: context.tBrand),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ready · asks answered on this phone',
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                    '${store.precinct} · ${store.householdName ?? "neighbour"}'
                    ' · ${stats.points} points · ${stats.pending} to finish',
                    style: TextStyle(fontSize: 12, color: context.tMuted)),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _quickActions(BuildContext context) {
    final actions = <(IconData, String, RouteSettings)>[
      (Icons.camera_alt, 'Scan an item', const RouteSettings(name: '/scan')),
      (Icons.recycling, 'My collection', const RouteSettings(name: '/collection')),
      (Icons.volunteer_activism, 'Circular Hub', const RouteSettings(name: '/hub')),
      (Icons.report_problem, 'Report a problem', const RouteSettings(name: '/report')),
      (Icons.forum, 'Community Board', const RouteSettings(name: '/board')),
      (Icons.pets, 'Cat Dex', const RouteSettings(name: '/cat-dex')),
    ];
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.9,
      children: [
        for (final (icon, label, route) in actions) _tile(context, icon, label, route),
      ],
    );
  }

  Widget _tile(BuildContext context, IconData icon, String label, RouteSettings route) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.pushNamed(context, route.name!),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: context.tBrand),
              const SizedBox(height: 6),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _impact(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Points earned', '${stats.points}'),
            _row('Tasks finished', '${stats.done}'),
            _row('Open hazard reports', '${store.openReports}'),
            _row('Items shared on the Hub', '${store.hubListings.length}'),
            _row('Items you taught the scanner', '${store.taughtRefs.length}'),
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

/// Stats the Home screen needs from the CollectionStore.
class CollectionStats extends ChangeNotifier {
  int points = 0;
  int pending = 0;
  int done = 0;

  void refresh(int p, int pend, int d) {
    points = p;
    pending = pend;
    done = d;
    notifyListeners();
  }
}
