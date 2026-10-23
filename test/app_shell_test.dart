/// WO-01 app-shell tests: branded splash, StaffGuard, the board-24 tour
/// page-1 copy, and the map stream-filter helper.
///
/// Run: `flutter test test/app_shell_test.dart`
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:township_of_tomorrow/main.dart';
import 'package:township_of_tomorrow/screens/map_screen.dart';
import 'package:township_of_tomorrow/screens/splash_screen.dart';
import 'package:township_of_tomorrow/screens/tour_overlay.dart';
import 'package:township_of_tomorrow/store/township_store.dart';

void main() {
  testWidgets('branded splash renders wordmark and tagline', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));

    expect(find.text('Township of Tomorrow'), findsOneWidget);
    expect(find.text('Point, sort, prove — all on device'), findsOneWidget);
    expect(find.byIcon(Icons.recycling), findsOneWidget);
    // Animations enabled by default → the branded spinner is shown.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('splash drops spinner and motion when animations are off',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: SplashScreen(),
      ),
    ));

    // Reduce-motion: wordmark + tagline stay, indeterminate motion goes.
    expect(find.text('Township of Tomorrow'), findsOneWidget);
    expect(find.text('Point, sort, prove — all on device'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('StaffGuard blocks non-staff and links to Profile',
      (tester) async {
    final store = TownshipStore(); // isStaff defaults to false
    await tester.pumpWidget(MaterialApp(
      routes: {
        '/profile': (_) => const Scaffold(body: Text('PROFILE PAGE')),
      },
      home: StaffGuard(
        store: store,
        child: const Text('OPERATOR CONTENT'),
      ),
    ));

    // Non-staff: the guarded content never renders; the copy + shortcut do.
    expect(find.text('OPERATOR CONTENT'), findsNothing);
    expect(find.text('Staff access only'), findsOneWidget);
    expect(
      find.text('This area is for township staff. Turn on Staff mode in '
          'Profile to continue.'),
      findsOneWidget,
    );

    // 'Open profile' pushes the profile route.
    await tester.tap(find.text('Open profile'));
    await tester.pumpAndSettle();
    expect(find.text('PROFILE PAGE'), findsOneWidget);
    Navigator.of(tester.element(find.text('PROFILE PAGE'))).pop();
    await tester.pumpAndSettle();

    // The guard rebuilds on store changes: Staff mode unlocks the route.
    store.setStaff(true);
    await tester.pump();
    expect(find.text('OPERATOR CONTENT'), findsOneWidget);
    expect(find.text('Staff access only'), findsNothing);
  });

  testWidgets('tour page-1 copy matches board 24', (tester) async {
    final store = TownshipStore();
    await tester.pumpWidget(MaterialApp(home: TourOverlay(store: store)));

    expect(find.text('Scan first'), findsOneWidget);
    expect(
      find.text(
        'Point your camera at the item in good light. The scanner answers '
        'from models on this phone — no cloud, no uploads.',
      ),
      findsOneWidget,
    );
    // The old model-internals wording is gone.
    expect(find.textContaining('EfficientDet'), findsNothing);
    expect(find.textContaining('No internet needed'), findsNothing);
  });

  test('map filter helper returns the right pins and can be empty', () {
    expect(MapScreen.visibleBinCount(null), 5); // All → every bin + home pin
    expect(MapScreen.visibleBinCount('Recyclable'), 1);
    expect(MapScreen.visibleBinCount('Organic'), 1);
    expect(MapScreen.visibleBinCount('Hub'), 1);
    // A legend stream with no drop-off site filters down to nothing —
    // that's the empty-panel case.
    expect(MapScreen.visibleBinCount('Landfill'), 0);
    expect(MapScreen.visibleBinCount('NotAStream'), 0);
  });
}
