/// WO-02 report loop tests: validation gate, receipt swap + persistence,
/// resolve → share-once → /board, and the board-38/39 empty variants.
///
/// TownshipStore never gets `load()`ed, so its `_file` stays null and no
/// `path_provider` call is ever reached. The community board store is
/// TempDir-backed (`storageDir:`), and every store file the board screen's
/// `initState`-triggered `load()` might read is pre-seeded synchronously, so
/// the assertions hold whether or not that IO completes inside the fake-async
/// widget-test zone.
///
/// Run: `flutter test test/report_flow_test.dart`
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:township_of_tomorrow/community_board/board_models.dart';
import 'package:township_of_tomorrow/community_board/board_screen.dart';
import 'package:township_of_tomorrow/community_board/board_store.dart';
import 'package:township_of_tomorrow/community_board/synthetic_seed.dart';
import 'package:township_of_tomorrow/screens/collection_screen.dart';
import 'package:township_of_tomorrow/screens/report_screen.dart';
import 'package:township_of_tomorrow/screens/report_status_screen.dart';
import 'package:township_of_tomorrow/store/collection_store.dart';
import 'package:township_of_tomorrow/store/township_store.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wo02_report_flow');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  FilledButton submitButton(WidgetTester tester) =>
      tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Submit report'));

  testWidgets('empty description blocks submit', (tester) async {
    // Tall viewport: submit + helper text sit at the bottom of the form
    // ListView and must be on-screen to be built and asserted.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final store = TownshipStore();
    await tester.pumpWidget(MaterialApp(home: ReportScreen(store: store)));

    // The AppBar carries the "My reports" receipt action.
    expect(find.byTooltip('My reports'), findsOneWidget);

    // Empty (and whitespace-only) description: submit disabled + helper text.
    expect(submitButton(tester).onPressed, isNull);
    expect(find.text('Describe the problem before submitting.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(submitButton(tester).onPressed, isNull);
    expect(store.reports, isEmpty);

    // Any real text unlocks submit.
    await tester.enterText(find.byType(TextField), 'Overflowing bin by the market');
    await tester.pump();
    expect(submitButton(tester).onPressed, isNotNull);
  });

  testWidgets('submit shows the receipt and persists exactly one report',
      (tester) async {
    final store = TownshipStore();
    store.setPrecinct('Precinct 3');
    await tester.pumpWidget(MaterialApp(home: ReportScreen(store: store)));

    await tester.enterText(
        find.byType(TextField), '  Street light out on Kestrel Lane  ');
    final submit = find.widgetWithText(FilledButton, 'Submit report');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pump();

    // Exactly one report, trimmed, precinct-only location (lat/lng null).
    expect(store.reports, hasLength(1));
    final report = store.reports.single;
    expect(report.description, 'Street light out on Kestrel Lane');
    expect(report.precinct, 'Precinct 3');
    expect(report.lat, isNull);
    expect(report.lng, isNull);
    expect(report.status, 'submitted');

    // Receipt state (no SnackBar, no pop).
    expect(find.text('Report logged — this is your receipt'), findsOneWidget);
    expect(find.text('Ref ${reportRef(report.id)}'), findsOneWidget);
    expect(find.text('Status: Received — logged just now'), findsOneWidget);
    expect(find.text('Received'), findsOneWidget);
    expect(find.text('In review'), findsOneWidget);
    expect(find.text('Resolved'), findsOneWidget);
    expect(find.text('Back to home'), findsOneWidget);
    expect(find.text('Track my report'), findsOneWidget);
    expect(find.text('New report'), findsOneWidget);

    // New report resets the form without duplicating the stored report.
    await tester.tap(find.text('New report'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(store.reports, hasLength(1));
  });

  testWidgets('resolved report shares once and pushes /board', (tester) async {
    final township = TownshipStore();
    final report = township.addReport(
        category: 'Street light out', description: 'Lamp dark by the stop');
    township.resolveReport(report.id);
    final board = CommunityBoardStore(storageDir: tmp);

    await tester.pumpWidget(MaterialApp(
      routes: {
        '/board': (_) => const Scaffold(body: Text('BOARD-SCREEN')),
      },
      home: ReportStatusScreen(store: township, board: board),
    ));

    expect(find.text('Resolved'), findsWidgets);
    expect(find.text('Status changes appear here as operators update the queue.'),
        findsWidgets);

    final share = find.widgetWithText(FilledButton, 'Share resolution to board');
    await tester.ensureVisible(share);
    await tester.pumpAndSettle();
    await tester.tap(share);
    await tester.pumpAndSettle();
    expect(find.text('BOARD-SCREEN'), findsOneWidget);

    final shared = board.byId('report-${report.id}');
    expect(shared, isNotNull);
    expect(shared!.title, 'Resolved: Street light out — Precinct 1');
    expect(shared.category, 'Facilities');
    expect(shared.authorLabel, 'Township Operations');
    expect(shared.isSynthetic, isFalse);
    expect(board.postCount, 1);

    // Back to the status screen; sharing again must not duplicate the post.
    Navigator.of(tester.element(find.text('BOARD-SCREEN'))).pop();
    await tester.pumpAndSettle();
    final shareAgain =
        find.widgetWithText(FilledButton, 'Share resolution to board');
    await tester.ensureVisible(shareAgain);
    await tester.tap(shareAgain);
    await tester.pumpAndSettle();
    expect(find.text('Already shared to the community board'), findsOneWidget);
    expect(board.postCount, 1);
    expect(find.text('BOARD-SCREEN'), findsOneWidget);
  });

  // Board 38: collection empty. Split from the board empty test on purpose —
  // after an in-test route push, a later pumpWidget keeps the pushed route on
  // top of the replaced root (Navigator state survives the root update), so
  // the two trees must not share one testWidgets body.
  testWidgets('collection empty variant renders its exact copy (board 38)',
      (tester) async {
    final collection = CollectionStore();
    await tester.pumpWidget(MaterialApp(
      routes: {
        '/scan': (_) => const Scaffold(body: Text('SCAN-SCREEN')),
      },
      home: Scaffold(body: CollectionScreen(store: collection)),
    ));

    expect(find.text('0 points'), findsOneWidget); // header kept
    expect(find.text('0 pending'), findsOneWidget);
    expect(find.text('Nothing collected yet'), findsOneWidget);
    expect(find.text('Log your first item after a scan — your streak starts '
        'with bin no. 1.'), findsOneWidget);
    await tester.tap(find.text('Start scanning'));
    await tester.pumpAndSettle();
    expect(find.text('SCAN-SCREEN'), findsOneWidget);
  });

  // Board 39: community board empty.
  testWidgets('board empty variant renders its exact copy (board 39)',
      (tester) async {
    final boardDir = Directory('${tmp.path}/board')..createSync();
    // An on-disk empty list keeps the state empty whether or not the screen's
    // initState `load()` completes inside the fake-async zone.
    File('${boardDir.path}/${CommunityBoardStore.fileName}')
        .writeAsStringSync('[]');
    final board = CommunityBoardStore(storageDir: boardDir);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CommunityBoardScreen(store: board)),
    ));

    expect(find.text('No posters around you yet'), findsOneWidget);
    expect(find.text('See something the neighbourhood should know? Start the '
        'first post.'), findsOneWidget);

    // "Write the first post" opens the compose sheet.
    await tester.tap(find.text('Write the first post'));
    await tester.pumpAndSettle();
    expect(
        find.text('Stored on this device. Your post is marked as '
            'resident-written, not synthetic.'),
        findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // "Browse rules" opens the local rules sheet.
    await tester.tap(find.text('Browse rules'));
    await tester.pumpAndSettle();
    expect(find.text('Community board rules'), findsOneWidget);
  });

  testWidgets('board filter that matches nothing offers Clear all',
      (tester) async {
    final boardDir = Directory('${tmp.path}/board_seed')..createSync();
    File('${boardDir.path}/${CommunityBoardStore.fileName}')
        .writeAsStringSync(jsonEncode(kSyntheticBoardSeed));
    final board = CommunityBoardStore(storageDir: boardDir);
    await tester.runAsync(() => board.load()); // real IO off the fake zone
    expect(board.postCount, kSyntheticBoardSeed.length);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CommunityBoardScreen(store: board)),
    ));
    expect(find.textContaining('Deep pothole'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzz-no-such-post');
    await tester.pump();
    expect(find.text('Nothing matches this filter'), findsOneWidget);
    await tester.tap(find.text('Clear all'));
    await tester.pump();
    expect(find.text('Nothing matches this filter'), findsNothing);
    expect(find.textContaining('Deep pothole'), findsOneWidget);
  });

  group('board store contracts (WO-02)', () {
    test('addPost is idempotent by id and returns the stored post', () async {
      final store = CommunityBoardStore(storageDir: tmp);
      await store.load();
      final seeded = store.postCount;

      final first = await store.addPost(BoardPost(
        id: 'report-77',
        title: 'Resolved: Street light out — Precinct 1',
        body: 'original',
        category: 'Facilities',
        precinct: 'Precinct 1',
        authorLabel: 'Township Operations',
        createdAt: DateTime.utc(2026, 10, 20, 9),
        isSynthetic: false,
      ));
      final second = await store.addPost(BoardPost(
        id: 'report-77', // same id, different payload — must not duplicate
        title: 'duplicate attempt',
        body: 'duplicate',
        category: 'Events',
        precinct: 'Precinct 2',
        authorLabel: 'Resident A-99',
        createdAt: DateTime.utc(2026, 10, 21, 9),
        isSynthetic: false,
      ));

      expect(identical(first, second), isTrue,
          reason: 'the stored post is returned, not the new instance');
      expect(second.title, 'Resolved: Street light out — Precinct 1');
      expect(store.postCount, seeded + 1);
    });

    test('clearAll empties the board and resetToSeed restores the seed',
        () async {
      final store = CommunityBoardStore(storageDir: tmp);
      await store.load();
      expect(store.postCount, kSyntheticBoardSeed.length);

      await store.clearAll();
      expect(store.postCount, 0);
      expect(store.posts, isEmpty);

      await store.resetToSeed();
      expect(store.postCount, kSyntheticBoardSeed.length);
      expect(store.posts.map((p) => p.id).toList(),
          kSyntheticBoardSeed.map((j) => j['id'] as String).toList());
    });
  });
}
