/// Profile + settings: identity card, precinct picker, the appearance
/// (theme) picker, the staff switch that makes /operator reachable from
/// inside the app (the checklist's fix for the unreachable ops tier), and
/// the privacy promise. Board 14.
library;

import 'package:flutter/material.dart';

import '../store/township_store.dart';
import '../theme.dart';

/// Palette (board 14): every surface / copy colour comes from the frozen
/// tokens through [TownshipPalette], so this screen follows the active
/// light/dark theme — see `theme.dart`.

/// The three appearance choices, in the order they are offered.
const List<(String, String)> _themeOptions = [
  ('system', 'System default'),
  ('light', 'Light'),
  ('dark', 'Dark'),
];

class ProfileScreen extends StatelessWidget {
  final TownshipStore store;
  const ProfileScreen({super.key, required this.store});

  static String _initial(String? name) {
    final n = name?.trim() ?? '';
    return n.isEmpty ? 'R' : n.characters.first.toUpperCase();
  }

  /// Label for the stored appearance setting; unknown values read as the
  /// default the app actually falls back to.
  static String _themeLabel(String mode) => _themeOptions
      .firstWhere((o) => o.$1 == mode, orElse: () => _themeOptions.first)
      .$2;

  @override
  Widget build(BuildContext context) {
    final name = store.householdName?.trim() ?? '';
    final address = store.householdAddress.trim();
    final householdLine = [
      if (name.isNotEmpty) name,
      if (address.isNotEmpty) address,
    ].join(' · ');

    return FocusTraversalGroup(
      // Explicit avatar → appearance → staff → privacy keyboard focus order.
      policy: OrderedTraversalPolicy(),
      child: AnimatedBuilder(
        animation: store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── identity card ────────────────────────────────────────────
            FocusTraversalOrder(
              order: const NumericFocusOrder(0),
              child: _flatCard(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: context.tScheme.primary,
                            child: Text(
                              _initial(store.householdName),
                              // onPrimary is white in light and the deep
                              // green in dark — both clear 4.5:1 on the seed.
                              style: TextStyle(
                                color: context.tScheme.onPrimary,
                                fontSize: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name.isEmpty ? 'Resident' : name,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: context.tInk,
                                      ),
                                ),
                                Text(
                                  store.precinct,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: context.tMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: context.tHairline),
                    ListTile(
                      leading: Icon(
                        Icons.home_outlined,
                        color: context.tMuted,
                      ),
                      title: Text(
                        'Household',
                        style: TextStyle(color: context.tInk),
                      ),
                      subtitle: householdLine.isEmpty
                          ? null
                          : Text(
                              householdLine,
                              style: TextStyle(
                                fontSize: 13,
                                color: context.tMuted,
                              ),
                            ),
                    ),
                    Divider(height: 1, color: context.tHairline),
                    ListTile(
                      leading: Icon(
                        Icons.location_city,
                        color: context.tMuted,
                      ),
                      title: Text(
                        'Precinct',
                        style: TextStyle(color: context.tInk),
                      ),
                      subtitle: Text(
                        store.precinct,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.tMuted,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: context.tMuted,
                      ),
                      onTap: () async {
                        final p = await showDialog<String>(
                          context: context,
                          builder: (ctx) => SimpleDialog(
                            title: const Text('Choose precinct'),
                            children: [
                              for (final p in TownshipStore.precincts)
                                SimpleDialogOption(
                                  onPressed: () => Navigator.pop(ctx, p),
                                  child: Text(p),
                                ),
                            ],
                          ),
                        );
                        if (p != null) store.setPrecinct(p);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // ── appearance card ──────────────────────────────────────────
            Text(
              'Appearance',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold, color: context.tInk),
            ),
            const SizedBox(height: 8),
            FocusTraversalOrder(
              order: const NumericFocusOrder(1),
              child: _flatCard(
                context,
                child: ListTile(
                  leading: Icon(
                    Icons.brightness_6_outlined,
                    color: context.tMuted,
                  ),
                  title: Text(
                    'Theme',
                    style: TextStyle(color: context.tInk),
                  ),
                  subtitle: Text(
                    _themeLabel(store.themeMode),
                    style: TextStyle(fontSize: 13, color: context.tMuted),
                  ),
                  // No chevron: the precinct row owns the picker affordance,
                  // this one opens the same style of dialog on the whole row.
                  onTap: () async {
                    final m = await showDialog<String>(
                      context: context,
                      builder: (ctx) => SimpleDialog(
                        title: const Text('Choose theme'),
                        children: [
                          for (final (value, label) in _themeOptions)
                            SimpleDialogOption(
                              onPressed: () => Navigator.pop(ctx, value),
                              child: Text(label),
                            ),
                        ],
                      ),
                    );
                    if (m != null) store.setThemeMode(m);
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            // ── staff card ───────────────────────────────────────────────
            Text(
              'Township staff',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold, color: context.tInk),
            ),
            const SizedBox(height: 8),
            FocusTraversalOrder(
              order: const NumericFocusOrder(2),
              child: _flatCard(
                context,
                color: store.isStaff ? context.tTintGreen : context.tCard,
                child: Semantics(
                  toggled: store.isStaff,
                  child: SwitchListTile(
                    secondary: Icon(Icons.settings, color: context.tMuted),
                    title: Text(
                      'Staff mode',
                      style: TextStyle(color: context.tInk),
                    ),
                    subtitle: Text(
                      store.isStaff
                          ? 'On — operator dashboard available'
                          : 'Off — open the operator tier only when on',
                      style: TextStyle(fontSize: 13, color: context.tMuted),
                    ),
                    value: store.isStaff,
                    onChanged: (v) {
                      // Persist first; the /operator route guard (main.dart)
                      // is the deep-link safety net either way.
                      store.setStaff(v);
                      if (v && context.mounted) {
                        Navigator.of(context).pushNamed('/operator');
                      }
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // ── privacy card ─────────────────────────────────────────────
            Text(
              'Privacy',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold, color: context.tInk),
            ),
            const SizedBox(height: 8),
            FocusTraversalOrder(
              order: const NumericFocusOrder(3),
              child: _flatCard(
                context,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'All AI inference happens on this phone. Scan photos never '
                    'leave the device. Features that share data (the Hub) always '
                    'ask first.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: context.tInk,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Board-14 card: flat, radius 12, hairline border — surfaces follow the
  /// active theme (white card / ink hairline in light, dark card in dark).
  static Widget _flatCard(
    BuildContext context, {
    required Widget child,
    Color? color,
  }) => Card(
    elevation: 0,
    color: color ?? context.tCard,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: context.tHairline),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}
