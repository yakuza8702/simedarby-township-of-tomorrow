/// Precinct-map empty-state tests (board 41): the pin-count helper and the
/// empty-panel gate that hides the base "No pins in this area yet" variant
/// while the seeded bin list is populated.
///
/// PURE helper tests on purpose: `_Bin` rows are sourced from the
/// `static const MapScreen.bins` list (five drop-off sites), so there is no
/// injection seam to pump an empty bin set through yet — the predicate is
/// exercised directly instead, with the seam noted in the widget-side
/// comment. Pumping `MapScreen` itself would pull flutter_map's tile layer
/// into the test HTTP stack for no extra coverage of this logic.
///
/// Run: `flutter test test/map_states_test.dart`
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:township_of_tomorrow/screens/map_screen.dart';

void main() {
  test('visibleBinCount: seeded list is 5 unfiltered, per-stream counts match',
      () {
    expect(MapScreen.visibleBinCount(null), 5);
    expect(MapScreen.visibleBinCount('Recyclable'), 1);
    expect(MapScreen.visibleBinCount('Organic'), 1);
    expect(MapScreen.visibleBinCount('Hub'), 1);
    // Streams without a drop-off filter down to zero pins.
    expect(MapScreen.visibleBinCount('Landfill'), 0);
    expect(MapScreen.visibleBinCount('NotAStream'), 0);
  });

  test(
      'empty-panel gate: filtered-empty shows the overlay, unfiltered stays '
      'hidden while the bin list is seeded, base variant only when empty', () {
    // Filter with no drop-off → the filtered variant ('Nothing matches this
    // filter') covers the map, even though the full list is populated.
    expect(MapScreen.showEmptyPinsPanel('Landfill', binsEmpty: false), isTrue);
    expect(MapScreen.showEmptyPinsPanel('NotAStream', binsEmpty: false), isTrue);

    // No filter + 5 seeded bins → the panel must stay hidden (the dead
    // overlay this gate exists to prevent).
    expect(MapScreen.showEmptyPinsPanel(null, binsEmpty: false), isFalse,
        reason: 'seeded unfiltered view never shows the empty panel');

    // No filter + an actually empty bin list → base variant becomes
    // reachable ('No pins in this area yet'). This is the injection seam:
    // `MapScreen.bins` is a static const today, so only a future injected
    // bin set can drive it — the predicate itself is already correct.
    expect(MapScreen.showEmptyPinsPanel(null, binsEmpty: true), isTrue);
    expect(MapScreen.visibleBinCount(null), greaterThan(0),
        reason: 'the shipped seed keeps the base variant out of reach');
  });
}
