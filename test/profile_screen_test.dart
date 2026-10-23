/// Widget tests for ProfileScreen (WO-04): identity card with Resident
/// fallback + precinct, and the staff switch — ON persists isStaff and
/// pushes /operator, OFF only persists and stays put.
///
/// TownshipStore persists through path_provider; the platform channel is
/// mocked to a TempDir so no real app-documents dir is touched.
///
/// Run: `flutter test test/profile_screen_test.dart`
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:township_of_tomorrow/screens/profile_screen.dart';
import 'package:township_of_tomorrow/store/township_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');

  late Directory tmp;
  late TownshipStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('profile_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return tmp.path;
          }
          return null;
        });
    store = TownshipStore();
    await store.load();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<Map<String, dynamic>> readState(WidgetTester tester) async {
    final state = await tester.runAsync(() async {
      final f = File('${tmp.path}/township_state.json');
      expect(f.existsSync(), isTrue, reason: 'store should have persisted');
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    });
    return state!;
  }

  /// Let fire-and-forget store writes (real file IO) settle inside the
  /// fake-async widget-test zone.
  Future<void> flushWrites(WidgetTester tester) => tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );

  Widget harness() => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('Profile & settings')),
      body: ProfileScreen(store: store),
    ),
    routes: {
      '/operator': (_) =>
          const Scaffold(body: Center(child: Text('OPERATOR STUB'))),
    },
  );

  testWidgets('identity card shows Resident fallback and precinct', (
    tester,
  ) async {
    await tester.pumpWidget(harness());

    // Fallback identity: no household name yet.
    expect(find.text('Resident'), findsOneWidget);
    expect(find.text('R'), findsOneWidget); // avatar initial
    expect(find.text('Precinct 1'), findsNWidgets(2)); // header + row value
    expect(find.text('Household'), findsOneWidget);
    expect(find.text('Precinct'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget); // picker chevron
    expect(
      find.text('Off — open the operator tier only when on'),
      findsOneWidget,
    );
    expect(find.text('Privacy'), findsOneWidget);
    expect(
      find.textContaining('All AI inference happens on this phone'),
      findsOneWidget,
      reason: 'privacy copy must stay verbatim',
    );

    // Named household replaces the fallback everywhere.
    store.householdName = 'Ada Lovelace';
    store.householdAddress = '12 Canopy Lane';
    await tester.pumpWidget(harness());
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('A'), findsOneWidget); // avatar initial follows the name
    expect(find.text('Resident'), findsNothing);
  });

  testWidgets('staff ON navigates to /operator and OFF shows explicit state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(harness());

      expect(store.isStaff, isFalse);
      expect(
        Navigator.of(tester.element(find.byType(ProfileScreen))).canPop(),
        isFalse,
      );

      // ── ON: persists, announces, pushes /operator ──────────────────────
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(store.isStaff, isTrue, reason: 'ON must persist isStaff');
      expect(
        find.text('OPERATOR STUB'),
        findsOneWidget,
        reason: 'ON must push /operator',
      );
      expect(
        find.text('On — operator dashboard available'),
        findsNothing,
        reason: 'profile route is covered by the pushed /operator route',
      );

      // Back on profile: state is explicit and semantics announce it.
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.text('OPERATOR STUB'), findsNothing);
      expect(find.text('On — operator dashboard available'), findsOneWidget);
      final on = tester.getSemantics(find.byType(Switch)).getSemanticsData();
      expect(
        on.flagsCollection.isToggled,
        Tristate.isTrue,
        reason: 'toggle semantics must announce the toggled state',
      );
      expect(store.isStaff, isTrue);
      await flushWrites(tester);
      expect((await readState(tester))['isStaff'], isTrue);

      // ── OFF: persists only, no navigation ──────────────────────────────
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(store.isStaff, isFalse, reason: 'OFF must persist isStaff');
      expect(
        find.text('OPERATOR STUB'),
        findsNothing,
        reason: 'OFF must not navigate',
      );
      expect(
        Navigator.of(tester.element(find.byType(ProfileScreen))).canPop(),
        isFalse,
        reason: 'still on the profile screen',
      );
      expect(
        find.text('Off — open the operator tier only when on'),
        findsOneWidget,
      );
      final off = tester.getSemantics(find.byType(Switch)).getSemanticsData();
      expect(off.flagsCollection.isToggled, Tristate.isFalse);
      await flushWrites(tester);
      expect((await readState(tester))['isStaff'], isFalse);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('precinct picker row still opens the dialog and applies', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    expect(store.precinct, 'Precinct 1');
    await tester.tap(find.text('Precinct'));
    await tester.pumpAndSettle();
    expect(find.text('Choose precinct'), findsOneWidget);

    await tester.tap(find.text('Precinct 3'));
    await tester.pumpAndSettle();

    expect(store.precinct, 'Precinct 3');
    await flushWrites(tester);
    expect((await readState(tester))['precinct'], 'Precinct 3');
  });
}
