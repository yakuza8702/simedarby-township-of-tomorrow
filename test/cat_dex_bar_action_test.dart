/// Cat Dex persistent app-bar action tests (jury fix): a 'Log a sighting'
/// icon button joins the HOST app bar whenever the Dex shows at least one
/// sighting, sits inside the bar's action slot (48dp, flush trailing edge),
/// pushes the same LogSightingScreen as the shelf CTA, and steps aside
/// (never floats over) while another route is on top.
///
/// The host is pumped exactly the way the `/cat-dex` route in main.dart
/// builds it — `Scaffold(appBar: AppBar(title: Text('Cat Dex')), body: ...)`
/// — because the action anchors into that ancestor bar; a bare
/// `Scaffold(body: ...)` (the shape the older Dex tests use) has no bar to
/// join and must keep showing no action.
///
/// Run: `flutter test test/cat_dex_bar_action_test.dart`
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:township_of_tomorrow/cat_dex/cat_dex_screen.dart';
import 'package:township_of_tomorrow/cat_dex/cat_dex_store.dart';
import 'package:township_of_tomorrow/cat_dex/log_sighting_screen.dart';
import 'package:township_of_tomorrow/community_board/board_store.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('catdex_bar_action');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  /// The `/cat-dex` route wrapper's tree: host Scaffold + 'Cat Dex' app bar,
  /// Cat Dex screen as the body.
  Widget host(CommunityBoardStore board, CatDexStore store) => MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Cat Dex')),
          body: CatDexScreen(store: store, board: board),
        ),
      );

  Future<CatDexStore> seededStore() async {
    final store = CatDexStore(storageDir: tmp);
    await store.addSighting(
      id: 'cat-bar-1',
      label: 'cat',
      itemLabel: 'stray cat',
      precinct: 'Precinct 7',
      source: 'camera roll',
      originalPath: '${tmp.path}/src.png',
      stickerPath: '${tmp.path}/sticker.png',
    );
    return store;
  }

  testWidgets(
      'app-bar action shows with sightings, sits in the bar, opens the log flow',
      (tester) async {
    final store = await seededStore();
    final board = CommunityBoardStore(storageDir: tmp);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(host(board, store));
      await tester.pumpAndSettle();

      // Persistent action: icon button + tooltip/semantics, no visible Text
      // (the shelf CTA only exists on the empty Dex).
      final action = find.byTooltip('Log a sighting');
      expect(action, findsOneWidget);
      expect(find.bySemanticsLabel('Log a sighting'), findsOneWidget);
      expect(find.text('Log a sighting'), findsNothing,
          reason: 'the >0-sightings state has no text CTA to collide with');

      // Anchored INSIDE the host app bar: flush trailing edge, vertically
      // centered in the toolbar, >= the 44dp hit-target floor.
      final actionRect = tester.getRect(action);
      final barRect = tester.getRect(find.byType(AppBar));
      expect(actionRect.top, greaterThanOrEqualTo(barRect.top));
      expect(actionRect.bottom, lessThanOrEqualTo(barRect.bottom));
      expect(actionRect.right, closeTo(barRect.right, 0.01));
      expect(actionRect.width, greaterThanOrEqualTo(44));
      expect(actionRect.height, greaterThanOrEqualTo(44));

      // Same LogSightingScreen the empty-state CTA pushes.
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.byType(LogSightingScreen), findsOneWidget);
      expect(find.text('Choose from gallery'), findsOneWidget);
      expect(find.byTooltip('Log a sighting'), findsNothing,
          reason: 'the action steps aside while another route is on top');

      // Back: the action is back in the bar (the overlay entry survives the
      // push/pop cycle — the Navigator rearranges entries on every flush).
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(LogSightingScreen), findsNothing);
      expect(find.byTooltip('Log a sighting'), findsOneWidget);
      expect(tester.getRect(find.byTooltip('Log a sighting')).right,
          closeTo(barRect.right, 0.01));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('empty Dex keeps only the shelf CTA — no app-bar action',
      (tester) async {
    final store = CatDexStore(storageDir: tmp); // no sightings
    final board = CommunityBoardStore(storageDir: tmp);

    await tester.pumpWidget(host(board, store));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Log a sighting'), findsNothing,
        reason: 'the action only joins the bar once the Dex shows sightings');
    expect(find.text('The Dex is quiet'), findsOneWidget);
    expect(find.text('Log a sighting'), findsOneWidget); // shelf CTA
  });

  testWidgets('no host app bar → no action, even with sightings',
      (tester) async {
    final store = await seededStore();
    final board = CommunityBoardStore(storageDir: tmp);

    // The bare-body shape the older Dex tests pump: nothing to anchor into.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CatDexScreen(store: store, board: board)),
    ));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Log a sighting'), findsNothing);
    expect(find.byType(CatDexScreen), findsOneWidget);
  });
}
