/// WO-07 operator loop tests: scoped stats that sum to the scope total, a
/// precinct-filtered queue split from 'Recently resolved', state-driven
/// actions, the computed plan card, and the resolve → exactly-one-board-notice
/// contract.
///
/// TownshipStore / CollectionStore are never `load()`ed, so their `_file`
/// stays null and `path_provider` is never reached. The community board is
/// TempDir-backed (`storageDir:`) and likewise left un-loaded: `addPost` still
/// stores the notice in the injected store (its `save()` is a no-op with no
/// file), which keeps all IO inside the fake-async widget-test zone.
///
/// Run: `flutter test test/operator_loop_test.dart`
library;

import 'dart:io';
import 'dart:math' show pow;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:township_of_tomorrow/community_board/board_store.dart';
import 'package:township_of_tomorrow/screens/operator_dashboard.dart';
import 'package:township_of_tomorrow/store/collection_store.dart';
import 'package:township_of_tomorrow/store/township_store.dart';

/// Collection store with a scripted `pending` count — the plan card's task
/// number can't be produced through `CollectionStore.add()` in a VM test
/// (that path needs the native Go core), so the getter is stubbed instead.
class _PendingCollection extends CollectionStore {
  _PendingCollection(this._stubbed);
  final int _stubbed;

  @override
  int get pending => _stubbed;
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wo07_operator_loop');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  /// Tall viewport so every queue card is built (ListView builds lazily) and
  /// injected stores so no plugin channel is ever touched.
  Future<void> pumpDashboard(
    WidgetTester tester, {
    required TownshipStore township,
    CollectionStore? collection,
    CommunityBoardStore? board,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OperatorDashboard(
          store: township,
          collection: collection ?? CollectionStore(),
          board: board ?? CommunityBoardStore(storageDir: tmp),
        ),
      ),
    ));
    await tester.pump();
  }

  /// The number rendered inside stat tile `which` ('open' / 'triaged' / 'resolved').
  int statValue(WidgetTester tester, String which) {
    final card = find.byKey(ValueKey('operator-stat-$which'));
    expect(card, findsOneWidget, reason: 'stat tile $which is on screen');
    final texts = tester.widgetList<Text>(
        find.descendant(of: card, matching: find.byType(Text)));
    final values = [for (final t in texts) int.tryParse(t.data ?? '')]
        .whereType<int>()
        .toList();
    expect(values, isNotEmpty,
        reason: 'stat $which renders a numeric value');
    return values.first;
  }

  // Required test 1.
  testWidgets('stats sum to total and exclude in-review from open',
      (tester) async {
    final township = TownshipStore();
    township.setPrecinct('Precinct 1');
    township.addReport(
        category: 'Illegal dumping',
        description: 'Alpha submitted P1',
        severity: 'high');
    township.addReport(
        category: 'Bin overflowing',
        description: 'Bravo submitted P1',
        severity: 'medium');
    final inReview = township.addReport(
        category: 'Street light out',
        description: 'Charlie reviewed P1',
        severity: 'low');
    township.triageReport(inReview.id);
    final resolved = township.addReport(
        category: 'Pothole', description: 'Delta resolved P1', severity: 'low');
    township.resolveReport(resolved.id);
    township.setPrecinct('Precinct 2');
    township.addReport(
        category: 'Graffiti', description: 'Echo submitted P2', severity: 'low');
    township.setPrecinct('Precinct 1');

    await pumpDashboard(tester, township: township);

    // Scoped to My precinct: the P2 report is not counted anywhere.
    expect(find.text('Echo submitted P2'), findsNothing);
    final scope = operatorScopeReports(township.reports, 'Precinct 1',
        allPrecincts: false);
    expect(scope, hasLength(4));

    final open = statValue(tester, 'open');
    final inReviewCount = statValue(tester, 'triaged');
    final resolvedCount = statValue(tester, 'resolved');
    expect(open, 2, reason: 'open counts submitted ONLY');
    expect(inReviewCount, 1);
    expect(resolvedCount, 1);
    expect(open + inReviewCount + resolvedCount, scope.length,
        reason: 'the stat row totals the report count');
    expect(open,
        isNot(scope.where((r) => r.status != 'resolved').length),
        reason: 'an in-review report is never double-counted as open');

    // The scope control re-scopes the whole stat row.
    await tester.tap(find.text('All precincts'));
    await tester.pump();
    final allOpen = statValue(tester, 'open');
    final allInReview = statValue(tester, 'triaged');
    final allResolved = statValue(tester, 'resolved');
    expect(allOpen, 3);
    expect(allInReview, 1);
    expect(allResolved, 1);
    expect(allOpen + allInReview + allResolved, township.reports.length);
    expect(find.text('Echo submitted P2'), findsOneWidget);
  });

  // Required test 2.
  testWidgets('queue filters by precinct and resolved moves to its own section',
      (tester) async {
    final township = TownshipStore();
    township.setPrecinct('Precinct 1');
    final alpha = township.addReport(
        category: 'Illegal dumping', description: 'Alpha one P1');
    final charlie = township.addReport(
        category: 'Bin overflowing', description: 'Charlie reviewed P1');
    township.triageReport(charlie.id);
    final delta = township.addReport(
        category: 'Pothole', description: 'Delta resolved P1');
    township.resolveReport(delta.id);
    township.setPrecinct('Precinct 2');
    final beta = township.addReport(
        category: 'Street light out', description: 'Beta submitted P2');
    township.setPrecinct('Precinct 1');

    await pumpDashboard(tester, township: township);

    // Precinct filter: P1 work in, P2 work out.
    expect(find.text('Alpha one P1'), findsOneWidget);
    expect(find.text('Charlie reviewed P1'), findsOneWidget);
    expect(find.text('Beta submitted P2'), findsNothing);

    // The resolved card lives under 'Recently resolved', below the queue.
    final queueHeading = find.text('Assessment queue');
    final resolvedHeading = find.text('Recently resolved');
    expect(queueHeading, findsOneWidget);
    expect(resolvedHeading, findsOneWidget);
    final deltaText = find.text('Delta resolved P1');
    expect(deltaText, findsOneWidget);
    expect(
        tester.getTopLeft(deltaText).dy,
        greaterThan(tester.getTopLeft(resolvedHeading).dy),
        reason: 'resolved card sits under its own heading');
    expect(
        tester.getTopLeft(deltaText).dy,
        greaterThan(tester.getTopLeft(queueHeading).dy));

    // Resolved → status chip only, no action buttons.
    final deltaCard =
        find.ancestor(of: deltaText, matching: find.byType(Card)).first;
    expect(find.descendant(of: deltaCard, matching: find.byType(FilledButton)),
        findsNothing);
    expect(find.descendant(of: deltaCard, matching: find.byType(OutlinedButton)),
        findsNothing);
    expect(find.descendant(of: deltaCard, matching: find.text('Resolved')),
        findsOneWidget);

    // Actions follow state: submitted → Review, in-review → Mark resolved.
    final reviewBtn = find.widgetWithText(FilledButton, 'Review');
    final markResolved = find.widgetWithText(OutlinedButton, 'Mark resolved');
    expect(reviewBtn, findsOneWidget);
    expect(markResolved, findsOneWidget);
    expect(tester.getSize(reviewBtn).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(markResolved).height, greaterThanOrEqualTo(44));

    // Review moves alpha across — the button ladder follows.
    await tester.ensureVisible(reviewBtn);
    await tester.pumpAndSettle();
    await tester.tap(reviewBtn);
    await tester.pump();
    expect(
        township.reports.firstWhere((r) => r.id == alpha.id).status,
        'triaged');
    expect(find.widgetWithText(FilledButton, 'Review'), findsNothing);
    expect(markResolved, findsNWidgets(2));

    // Scope toggle both ways.
    await tester.tap(find.text('All precincts'));
    await tester.pump();
    expect(find.text('Beta submitted P2'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Review'), findsOneWidget);
    await tester.tap(find.text('My precinct'));
    await tester.pump();
    expect(find.text('Beta submitted P2'), findsNothing);
    expect(township.reports.firstWhere((r) => r.id == beta.id).status,
        'submitted');
  });

  // Required test 3.
  testWidgets('resolving posts exactly one board notice', (tester) async {
    final township = TownshipStore()..setPrecinct('Precinct 1');
    final report = township.addReport(
        category: 'Bin overflowing',
        description: 'Overflow by the market',
        severity: 'high');
    final board = CommunityBoardStore(storageDir: tmp);
    expect(board.postCount, 0);

    final semantics = tester.ensureSemantics();

    await pumpDashboard(tester, township: township, board: board);

    // submitted → tonal Review first.
    final reviewBtn = find.widgetWithText(FilledButton, 'Review');
    await tester.ensureVisible(reviewBtn);
    await tester.pumpAndSettle();
    await tester.tap(reviewBtn);
    await tester.pump();
    expect(township.reports.single.status, 'triaged');

    // in-review → outlined Mark resolved. Double-tap before the rebuild: the
    // idempotent addPost contract must keep it at exactly one notice.
    final markResolved = find.widgetWithText(OutlinedButton, 'Mark resolved');
    await tester.ensureVisible(markResolved);
    await tester.pumpAndSettle();
    expect(tester.getSize(markResolved).height, greaterThanOrEqualTo(44));
    await tester.tap(markResolved);
    await tester.tap(markResolved);
    await tester.pumpAndSettle();

    expect(township.reports.single.status, 'resolved');
    expect(find.text('Resolved — posted to the community board'),
        findsOneWidget);

    // Exactly one notice, with the full board contract.
    expect(board.postCount, 1);
    final post = board.byId('report-${report.id}');
    expect(post, isNotNull, reason: "notice id is 'report-<report id>'");
    expect(post!.title, 'Resolved: Bin overflowing — Precinct 1');
    expect(post.category, 'Facilities');
    expect(post.authorLabel, 'Township Operations');
    expect(post.isSynthetic, isFalse);
    expect(post.precinct, 'Precinct 1');

    // The card moved out of the queue into 'Recently resolved'.
    expect(find.text('Overflow by the market'), findsOneWidget);
    expect(find.text('Recently resolved'), findsOneWidget);
    expect(find.text('No reports in Precinct 1 — queue is clear.'),
        findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Mark resolved'), findsNothing);

    // Chips carry text labels for screen readers (never colour-only).
    expect(find.bySemanticsLabel(RegExp('Severity: high')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Status: Resolved')), findsOneWidget);
    semantics.dispose(); // end-of-test verification wants the handle gone here
  });

  // Pure queue math — the same helpers the widget above renders from.
  test('scope helpers: stats exclude in-review from open, queue drops resolved, '
      'resolved moves to its own section newest-first', () {
    final now = DateTime(2026, 10, 22, 8);
    HazardReport rep(String id, String status,
            {String precinct = 'Precinct 1',
            DateTime? resolvedAt,
            String severity = 'low'}) =>
        HazardReport(
          id: id,
          category: 'Category $id',
          description: 'Description $id',
          severity: severity,
          precinct: precinct,
          status: status,
          createdAt: now,
          resolvedAt: resolvedAt,
        );

    final all = [
      rep('a', 'submitted'),
      rep('b', 'submitted', precinct: 'Precinct 2'),
      rep('c', 'triaged'),
      rep('d', 'resolved', resolvedAt: now.add(const Duration(minutes: 1))),
      rep('e', 'resolved', resolvedAt: now.add(const Duration(minutes: 2))),
    ];

    final mine = operatorScopeReports(all, 'Precinct 1', allPrecincts: false);
    expect(mine.map((r) => r.id), ['a', 'c', 'd', 'e']);
    expect(operatorScopeReports(all, 'Precinct 1', allPrecincts: true),
        hasLength(5));

    final stats = operatorScopeStats(mine);
    expect(stats.open, 1);
    expect(stats.triaged, 1);
    expect(stats.resolved, 2);
    expect(stats.open + stats.triaged + stats.resolved, mine.length,
        reason: 'row totals the report count');
    expect(stats.open, isNot(operatorQueue(mine).length),
        reason: 'in-review is never counted as open');

    expect(operatorQueue(mine).map((r) => r.id), ['a', 'c'],
        reason: 'resolved reports leave the queue');
    expect(operatorRecentlyResolved(mine).map((r) => r.id), ['e', 'd'],
        reason: 'newest resolvedAt first');

    final many = [
      for (var i = 0; i < 8; i++)
        rep('r$i', 'resolved',
            resolvedAt: now.add(Duration(minutes: i))),
    ];
    final capped = operatorRecentlyResolved(many);
    expect(capped, hasLength(5), reason: 'at most 5 recently resolved');
    expect(capped.first.id, 'r7');
    expect(capped.last.id, 'r3');
    expect(operatorPriorityCount(mine), 0);
    expect(
        operatorPriorityCount(
            operatorQueue([rep('p', 'submitted', severity: 'high')])),
        1);
  });

  test('plan summary is computed and falls back to the no-route copy', () {
    expect(operatorPlanSummary(priority: 0, tasks: 0),
        'No route needed today — queue is clear.');
    expect(operatorPlanSummary(priority: 1, tasks: 0),
        '1 priority · 0 resident tasks · est. 8 min');
    expect(operatorPlanSummary(priority: 2, tasks: 3),
        '2 priority · 3 resident tasks · est. 22 min');
  });

  testWidgets(
      'empty queue copy is precinct-specific and the plan falls back to no route',
      (tester) async {
    final township = TownshipStore()..setPrecinct('Precinct 4');
    await pumpDashboard(tester, township: township);

    expect(
        find.text('Operator dashboard — Precinct 4'), findsOneWidget);
    expect(find.text('Operator desk · review reports and close the loop'),
        findsOneWidget);
    expect(find.text('My precinct'), findsOneWidget);
    expect(find.text('All precincts'), findsOneWidget);
    expect(find.text('Assessment queue'), findsOneWidget);
    expect(find.text('No reports in Precinct 4 — queue is clear.'),
        findsOneWidget);
    expect(find.text('Recently resolved'), findsNothing);
    expect(find.text("Today's collection plan"), findsOneWidget);
    expect(find.text('Route A — organics + recycling'), findsNothing);
    expect(find.text('No route needed today — queue is clear.'),
        findsOneWidget);
    expect(statValue(tester, 'open'), 0);
    expect(statValue(tester, 'triaged'), 0);
    expect(statValue(tester, 'resolved'), 0);

    // The empty copy follows the selected scope.
    await tester.tap(find.text('All precincts'));
    await tester.pump();
    expect(find.text('No reports in All precincts — queue is clear.'),
        findsOneWidget);
  });

  testWidgets('plan card is computed from priority reports and pending tasks',
      (tester) async {
    final township = TownshipStore()..setPrecinct('Precinct 1');
    township.addReport(
        category: 'Illegal dumping',
        description: 'High severity pile',
        severity: 'high');
    township.addReport(
        category: 'Graffiti', description: 'Low severity wall', severity: 'low');

    await pumpDashboard(
      tester,
      township: township,
      collection: _PendingCollection(2),
    );

    expect(find.text("Today's collection plan"), findsOneWidget);
    expect(find.text('Route A — organics + recycling'), findsOneWidget);
    expect(find.text('1 priority · 2 resident tasks · est. 12 min'),
        findsOneWidget);
    expect(find.text('No route needed today — queue is clear.'), findsNothing);
  });

  // ONE contrast assertion helper for every chip text/background pair the
  // dashboard renders: WCAG 2.1 contrast ratio computed straight from the
  // two ARGB colours (the text's alpha is composited over the background
  // first) — pure Dart math, no packages — asserted against the 4.5:1
  // small-text floor.
  double expectChipContrast(String what, Color text, Color bg) {
    double channel(double v) => v <= 0.03928
        ? v / 12.92
        : pow((v + 0.055) / 1.055, 2.4).toDouble();

    double luminance(double r, double g, double b) =>
        0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);

    // Composite the (possibly translucent) text colour over its background.
    final a = text.a;
    final r = text.r * a + bg.r * (1 - a);
    final g = text.g * a + bg.g * (1 - a);
    final b = text.b * a + bg.b * (1 - a);
    final l1 = luminance(r, g, b);
    final l2 = luminance(bg.r, bg.g, bg.b);
    final hi = l1 > l2 ? l1 : l2;
    final lo = l1 > l2 ? l2 : l1;
    final ratio = (hi + 0.05) / (lo + 0.05);
    expect(ratio, greaterThanOrEqualTo(4.5),
        reason: '$what is ${ratio.toStringAsFixed(2)}:1 — below 4.5:1');
    return ratio;
  }

  testWidgets(
      'chips use the pinned colours and every chip pair clears 4.5:1',
      (tester) async {
    final township = TownshipStore()..setPrecinct('Precinct 1');
    township.addReport(
        category: 'High case', description: 'High description', severity: 'high');
    township.addReport(
        category: 'Medium case',
        description: 'Medium description',
        severity: 'medium');
    township.addReport(
        category: 'Low case', description: 'Low description', severity: 'low');
    final inReview = township.addReport(
        category: 'Reviewed case',
        description: 'Reviewed description',
        severity: 'high');
    township.triageReport(inReview.id);
    final resolved = township.addReport(
        category: 'Resolved case',
        description: 'Resolved description',
        severity: 'low');
    township.resolveReport(resolved.id);

    await pumpDashboard(tester, township: township);

    // Chip readers scoped to one report card: the status-chip labels
    // ('In review' / 'Resolved') also appear in the stat row, and the severity
    // labels repeat across cards.
    Finder cardOf(String description) => find
        .ancestor(of: find.text(description), matching: find.byType(Card))
        .first;

    Color? chipBackgroundIn(Finder card, String label) {
      final deco = tester.widget<DecoratedBox>(
          find
              .ancestor(
                  of: find.text(label),
                  matching: find.descendant(
                      of: card, matching: find.byType(DecoratedBox)))
              .first);
      final d = deco.decoration;
      return d is BoxDecoration ? d.color : null;
    }

    Color? chipTextIn(Finder card, String label) => tester
        .widget<Text>(find.descendant(of: card, matching: find.text(label)))
        .style
        ?.color;

    void expectChip(Finder card, String label, Color bg, Color fg,
        {String? what}) {
      expect(chipBackgroundIn(card, label), bg, reason: '$label chip bg');
      expect(chipTextIn(card, label), fg, reason: '$label chip text');
      expectChipContrast(what ?? '$label chip', fg, bg);
    }

    // Severity chips: high / medium / low — low moved off white-on-#388E3C
    // (4.12:1) onto seed-on-tint (4.56:1); all three are 12px semibold.
    expectChip(cardOf('High description'), 'high',
        const Color(0xFFB71C1C), Colors.white);
    expectChip(cardOf('Medium description'), 'medium',
        const Color(0xFFF9A825), const Color(0xFF212121)); // ink on amber
    expectChip(cardOf('Low description'), 'low',
        const Color(0xFFE8F5E9), const Color(0xFF2E7D32)); // seed on tint
    for (final label in ['high', 'medium', 'low']) {
      final style = tester
          .widget<Text>(find.descendant(
              of: cardOf('${label[0].toUpperCase()}${label.substring(1)} description'),
              matching: find.text(label)))
          .style;
      expect(style?.fontSize, 12, reason: '$label chip is 12px');
      expect(style?.fontWeight, FontWeight.w600, reason: '$label chip w600');
    }

    // Status chips: in-review (ink on tint-blue) and resolved (seed on
    // tint-green) — the same pairs the resident status screen renders.
    expectChip(cardOf('Reviewed description'), 'In review',
        const Color(0xFFE3F2FD), Colors.black87);
    expectChip(cardOf('Resolved description'), 'Resolved',
        const Color(0xFFE8F5E9), const Color(0xFF2E7D32));

    // The card meta speaks the shared status vocabulary, not raw values.
    expect(find.text('Precinct 1 · In review · just now'), findsOneWidget);
    expect(find.text('Precinct 1 · Resolved · just now'), findsOneWidget);
    expect(find.textContaining('· submitted ·'), findsNothing);
    expect(find.textContaining('· triaged ·'), findsNothing);
  });
}
