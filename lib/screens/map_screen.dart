/// Precinct map — bin locations + the household's home pin on OpenStreetMap
/// raster tiles (flutter_map). Drag to pan, use the on-screen +/- buttons to
/// zoom, and tap any pin to open a small info sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../store/township_store.dart';
import '../theme.dart';

class _Bin {
  final String id;
  final String label; // what it accepts
  final LatLng location; // real-world coordinates near the precinct
  final String streamColor;
  const _Bin(this.id, this.label, this.location, this.streamColor);
}

const _streamColors = {
  'Recyclable': Color(0xFF1976D2),
  'Organic': Color(0xFF388E3C),
  'E-waste': Color(0xFF7B1FA2),
  'Hazardous': Color(0xFFD32F2F),
  'Landfill': Color(0xFF616161),
  'Hub': Color(0xFFF9A825),
};

/// Sheet text per stream key — the circular hub is the reusable stream.
const _streamNames = {
  'Recyclable': 'Recyclable',
  'Organic': 'Organic',
  'E-waste': 'E-waste',
  'Hazardous': 'Hazardous',
  'Landfill': 'Landfill',
  'Hub': 'Hub (Reusable)',
};

/// Map centre for the precinct; every pin sits within ~0.02° of this point.
const _mapCenter = LatLng(3.05, 101.55);

class MapScreen extends StatefulWidget {
  final TownshipStore store;
  const MapScreen({super.key, required this.store});

  static const bins = [
    _Bin('b1', 'Recycling drop-off (blue bin)', LatLng(3.052, 101.548), 'Recyclable'),
    _Bin('b2', 'Organics + compost bay', LatLng(3.048, 101.552), 'Organic'),
    _Bin('b3', 'E-waste drop-off point', LatLng(3.051, 101.553), 'E-waste'),
    _Bin('b4', 'Household hazardous collection', LatLng(3.049, 101.547), 'Hazardous'),
    _Bin('b5', 'PPP circular hub (share instead)', LatLng(3.050, 101.550), 'Hub'),
  ];

  @override
  State<MapScreen> createState() => _MapScreenState();

  /// Bins visible under [filter] (null / 'All' = every bin).
  static List<_Bin> _binsFor(String? filter) => filter == null
      ? bins
      : [for (final b in bins) if (b.streamColor == filter) b];

  /// Number of bin pins visible under [filter]; empty for a stream with no
  /// drop-off. Used by the pin badge and the empty-panel check (board 41).
  static int visibleBinCount(String? filter) => _binsFor(filter).length;

  /// Whether the empty-pins overlay should cover the map (board 41) — BOTH
  /// conditions must hold:
  ///  * zero pins are visible under [filter] (a stream with no drop-off, or
  ///    — with no filter — the bin list itself being [binsEmpty]), and
  ///  * in the NO-filter case, the bin list must actually be empty: the
  ///    seeded list always carries 5 drop-offs, so the unfiltered view keeps
  ///    its panel hidden and the base "No pins in this area yet" variant only
  ///    becomes reachable through an injected/empty bin set.
  ///
  /// Injection seam: [_Bin] rows come from the `static const` [bins] list
  /// today, so `binsEmpty` is `false` in the shipped app — tests drive the
  /// predicate directly (test/map_states_test.dart) until the bin list gains
  /// an injection point.
  static bool showEmptyPinsPanel(String? filter, {required bool binsEmpty}) {
    final visible = filter != null
        ? visibleBinCount(filter)
        : (binsEmpty ? 0 : visibleBinCount(null));
    return visible == 0 && (filter != null || binsEmpty);
  }
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();

  /// Active stream filter; null = 'All'. The home pin hides while filtering.
  String? _filter;

  bool get _filtering => _filter != null;

  int get _pinCount =>
      MapScreen.visibleBinCount(_filter) + (_filtering ? 0 : 1);

  /// 'Widen filter' / 'Clear all': drop the filter and reset zoom (board 41).
  void _clearFilter() {
    setState(() => _filter = null);
    _mapController.move(_mapCenter, 14);
  }

  // Home pin: the household's address, inside the same ~0.02° spread.
  static const _homeLocation = LatLng(3.0505, 101.5495);

  String get _homeName => widget.store.householdName?.trim() ?? '';
  String get _homeAddress => widget.store.address.trim();
  String get _homeLabel {
    final name = _homeName;
    final address = _homeAddress;
    if (name.isEmpty && address.isEmpty) return 'Home';
    if (address.isEmpty) return name;
    if (name.isEmpty) return address;
    return '$name · $address';
  }

  void _zoom(double delta) {
    final cam = _mapController.camera;
    final zoom = (cam.zoom + delta).clamp(3.0, 19.0).toDouble();
    _mapController.move(cam.center, zoom);
  }

  void _showSiteSheet({
    required String title,
    String? subtitle,
    required List<String> streams,
  }) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(subtitle, style: Theme.of(ctx).textTheme.bodySmall),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in streams)
                    Chip(
                      backgroundColor:
                          _streamColors[s]!.withValues(alpha: 0.18),
                      avatar: Icon(Icons.circle, size: 12, color: _streamColors[s]),
                      label: Text('Accepts: ${_streamNames[s]}'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('${widget.store.precinct} — bin locations',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
              ),
              Badge(label: Text('$_pinCount pins')),
            ],
          ),
        ),
        _filterBar(),
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: const MapOptions(
                  initialCenter: _mapCenter,
                  initialZoom: 14,
                  minZoom: 3,
                  maxZoom: 19,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName:
                        'com.townshipoftomorrow.township_of_tomorrow',
                    maxNativeZoom: 19,
                  ),
                  MarkerLayer(
                    markers: [
                      for (final b in MapScreen._binsFor(_filter))
                        Marker(
                          point: b.location,
                          width: 44,
                          height: 44,
                          child: Tooltip(
                            message: '${b.label} (${b.id})',
                            child: GestureDetector(
                              onTap: () => _showSiteSheet(
                                title: b.label,
                                subtitle:
                                    'Drop-off site ${b.id} · ${b.location.latitude.toStringAsFixed(4)}, ${b.location.longitude.toStringAsFixed(4)}',
                                streams: [b.streamColor],
                              ),
                              child: _pin(
                                color: _streamColors[b.streamColor]!,
                                icon: b.streamColor == 'Hub'
                                    ? Icons.volunteer_activism
                                    : Icons.delete_outline,
                              ),
                            ),
                          ),
                        ),
                      // Home pin belongs to the unfiltered precinct view —
                      // hide it while a stream filter is active (board 41).
                      if (!_filtering)
                        Marker(
                          point: _homeLocation,
                          width: 48,
                          height: 48,
                          child: Tooltip(
                            message: _homeLabel,
                            child: GestureDetector(
                              onTap: () => _showSiteSheet(
                                title: _homeName.isEmpty ? 'Home' : _homeName,
                                subtitle:
                                    _homeAddress.isEmpty ? null : _homeAddress,
                                streams: _streamColors.keys.toList(),
                              ),
                              child: _pin(
                                  color: const Color(0xFF3949AB),
                                  icon: Icons.home),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SimpleAttributionWidget(
                      source: Text('© OpenStreetMap contributors')),
                ],
              ),
              if (MapScreen.showEmptyPinsPanel(_filter,
                  binsEmpty: MapScreen.bins.isEmpty))
                Positioned.fill(
                  child: _EmptyPinsPanel(filtered: _filtering, onWiden: _clearFilter),
                ),
              Positioned(
                right: 12,
                bottom: 12,
                child: Column(
                  children: [
                    _zoomButton(Icons.add, () => _zoom(1)),
                    const SizedBox(height: 8),
                    _zoomButton(Icons.remove, () => _zoom(-1)),
                  ],
                ),
              ),
            ],
          ),
        ),
        _legend(),
      ],
    );
  }

  /// Stream filter chips (All + one per legend stream) between the header
  /// and the map (board 41).
  Widget _filterBar() => SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: ChoiceChip(
                label: const Text('All'),
                selected: _filter == null,
                onSelected: (_) => setState(() => _filter = null),
              ),
            ),
            for (final s in _streamColors.keys)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                child: ChoiceChip(
                  label: Text(_streamNames[s] ?? s),
                  selected: _filter == s,
                  onSelected: (_) => setState(() => _filter = s),
                ),
              ),
          ],
        ),
      );

  Widget _zoomButton(IconData icon, VoidCallback onTap) => Material(
        elevation: 3,
        color: Theme.of(context).colorScheme.surface,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 22),
          ),
        ),
      );

  Widget _pin({required Color color, required IconData icon}) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      );

  Widget _legend() => Builder(
        builder: (ctx) => Container(
        color: Theme.of(ctx).canvasColor,
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            for (final e in _streamColors.entries)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 12, height: 12,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: e.value),
                ),
                const SizedBox(width: 4),
                Text(e.key, style: const TextStyle(fontSize: 11)),
              ]),
          ],
        ),
      ));
}

/// Overlay shown when the (filtered) pin set is empty (board 41). The
/// filtered variant swaps in its own title and a 'Clear all' action; both
/// actions clear the filter and reset zoom.
class _EmptyPinsPanel extends StatelessWidget {
  final bool filtered;
  final VoidCallback onWiden;
  const _EmptyPinsPanel({required this.filtered, required this.onWiden});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        margin: const EdgeInsets.all(24),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                filtered ? Icons.filter_alt_off_outlined : Icons.place_outlined,
                size: 40,
                color: kNeutral600,
              ),
              const SizedBox(height: 12),
              Text(
                filtered
                    ? 'Nothing matches this filter'
                    : 'No pins in this area yet',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: kInk,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Zoom out or widen the precinct filter.',
                textAlign: TextAlign.center,
                style: TextStyle(color: kNeutral600, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onWiden,
                child: Text(filtered ? 'Clear all' : 'Widen filter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
