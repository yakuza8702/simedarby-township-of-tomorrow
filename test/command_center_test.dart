/// WO-08 command center tests: the mix is computed LIVE from CollectionStore
/// entries (the legacy `streamMix` argument must be ignored), the vision card
/// tells the truth (YOLO primary, EfficientDet fallback), and each incident
/// row opens the read-only drill-down sheet.
///
/// Both stores are injected — the App singleton is never constructed. The
/// Go-core bridge (`township/core`) is mocked so `CollectionStore.add` can
/// compute its placeholder pHash without a device.
///
/// Run: `flutter test test/command_center_test.dart`
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:township_of_tomorrow/screens/command_center_screen.dart';
import 'package:township_of_tomorrow/screens/report_status_screen.dart'
    show reportRef;
import 'package:township_of_tomorrow/store/collection_store.dart';
import 'package:township_of_tomorrow/store/township_store.dart';
import 'package:township_of_tomorrow/types.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const coreChannel = MethodChannel('township/core');

  late TownshipStore store;
  late CollectionStore collection;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(coreChannel, (call) async {
      if (call.method == 'pHashFileDownscale') return 'feedface';
      return null;
    });
    store = TownshipStore();
    collection = CollectionStore();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(coreChannel, null);
  });

  Widget harness() => MaterialApp(
        home: Scaffold(
          body: CommandCenterScreen(
            store: store,
            collection: collection,
            // Legacy boot-time mix — the UI must NOT be driven by it.
            streamMix: const {'Landfill': 99},
          ),
        ),
      );

  /// Tall viewport: header + mix card + vision card + incident card must all
  /// be on-screen for the text/tap assertions below.
  void tallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('mix updates when collection entries change', (tester) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());

    expect(find.text('Resident scan mix (last scans)'), findsOneWidget);
    expect(find.text('No confirmed scans yet'), findsOneWidget);
    expect(find.text('Landfill'), findsNothing,
        reason: 'legacy streamMix argument must not drive the UI');
    expect(find.text('99%'), findsNothing);
    expect(find.textContaining('waste stream mix — no scans'), findsOneWidget,
        reason: 'SitRep starts from the live (empty) mix');

    await collection.add(
        itemLabel: 'bottle',
        category: WasteCategory.Recyclable,
        confidence: 92,
        photoPath: '/tmp/wo08_bottle.jpg');
    await tester.pump();

    expect(find.text('No confirmed scans yet'), findsNothing);
    expect(find.text('Recyclable'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('Landfill'), findsNothing);
    expect(find.textContaining('waste stream mix — Recyclable 1'),
        findsOneWidget,
        reason: 'SitRep follows the live mix');

    await collection.add(
        itemLabel: 'peel',
        category: WasteCategory.Organic,
        confidence: 88,
        photoPath: '/tmp/wo08_peel.jpg');
    await tester.pump();

    expect(find.text('Organic'), findsOneWidget);
    expect(find.text('Recyclable'), findsOneWidget);
    expect(find.text('50%'), findsNWidgets(2),
        reason: 'both bars recompute from the new total');
    expect(
        find.textContaining('waste stream mix — Recyclable 1, Organic 1'),
        findsOneWidget);
  });

  testWidgets('vision card names YOLO primary and EfficientDet fallback',
      (tester) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());

    expect(find.text('On-device vision parameters'), findsOneWidget);
    expect(
        find.text(
            'Primary detector: YOLO, 640×640 snapshot over 80 everyday '
            'object types'),
        findsOneWidget);
    expect(
        find.text('Fallback detector: EfficientDet-Lite0 int8, 320×320 — '
            'only when YOLO returns no boxes'),
        findsOneWidget);
    expect(
        find.text(
            'Identity bonus: MobileNet-v3 small embedder + resident-taught kNN'),
        findsOneWidget);
    expect(find.text('Label fallback: ML Kit on-device image labelling'),
        findsOneWidget);
    expect(find.text('Everything runs on this device · even with airplane mode on'),
        findsOneWidget);
    // The legacy claim (EfficientDet as primary engine) is gone.
    expect(find.textContaining('Primary engine: EfficientDet'), findsNothing);
  });

  testWidgets('tapping an incident opens the drill-down sheet',
      (tester) async {
    tallViewport(tester);
    // Disposed at the end of the body: addTearDown would run after the
    // framework's end-of-test semantics-handle verification.
    final semantics = tester.ensureSemantics();
    try {
      final report = store.addReport(
          category: 'Illegal dumping',
          description: 'Mattress dumped behind the market',
          severity: 'high');
      await tester.pumpWidget(harness());
      await tester.pump();

      expect(find.text('Incidents (1 open)'), findsOneWidget);
      expect(find.text('Nothing open — clean week'), findsNothing);
      final row = find.text('Illegal dumping — Precinct 1');
      expect(row, findsOneWidget);

      // Rows are >=44dp tall and expose category + precinct + status.
      final inkwell =
          find.ancestor(of: row, matching: find.byType(InkWell)).first;
      expect(tester.getSize(inkwell).height, greaterThanOrEqualTo(44));
      expect(
          find.bySemanticsLabel(
              RegExp('Illegal dumping, Precinct 1, status Received')),
          findsOneWidget,
          reason: 'semantic label carries category, precinct and status');

      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();

      // Drill-down sheet: ref, fields, photo state, timeline — read-only.
      expect(find.text('Ref ${reportRef(report.id)}'), findsOneWidget);
      expect(find.text('Category'), findsOneWidget);
      expect(find.text('Illegal dumping'), findsOneWidget);
      expect(find.text('Severity'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      expect(find.text('Precinct 1'), findsWidgets);
      expect(find.text('Mattress dumped behind the market'), findsOneWidget);
      expect(find.text('No photo attached'), findsOneWidget);
      expect(find.text('Received'), findsWidgets);
      expect(find.text('In review'), findsWidgets);
      expect(find.text('Resolved'), findsWidgets);
      expect(find.text('In progress'), findsOneWidget,
          reason: 'review step not reached yet');
      expect(find.text('Upcoming'), findsOneWidget,
          reason: 'resolve step not reached yet');
      expect(find.textContaining('Today ·'), findsWidgets,
          reason: 'Received step carries a real timestamp');
      expect(find.text('Read-only view — operators update the queue.'),
          findsOneWidget);
      expect(find.byType(FilledButton), findsNothing,
          reason: 'the drill-down is read-only — no action buttons');
      expect(find.widgetWithText(OutlinedButton, 'Close'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });
}
