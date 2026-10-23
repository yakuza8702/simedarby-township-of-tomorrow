/// Unit tests for the demo dataset service: deterministic seed and one-click
/// reset (WO-09).
///
/// `includeMedia: false` (the configuration pinned here) skips every
/// file-backed item — hub listings, collection entries and Cat Dex sightings —
/// so these are plain VM tests: no `path_provider`, no Go core, no media
/// written. Stores that persist (board, Cat Dex) get an injectable temp dir.
///
/// Run: `flutter test test/demo_data_test.dart`
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:township_of_tomorrow/community_board/board_models.dart';
import 'package:township_of_tomorrow/community_board/board_store.dart';
import 'package:township_of_tomorrow/cat_dex/cat_dex_store.dart';
import 'package:township_of_tomorrow/services/demo_data.dart';
import 'package:township_of_tomorrow/store/collection_store.dart';
import 'package:township_of_tomorrow/store/township_store.dart';
import 'package:township_of_tomorrow/types.dart';

void main() {
  late Directory tmp;
  late TownshipStore township;
  late CollectionStore collection;
  late CatDexStore catDex;
  late CommunityBoardStore board;
  late DemoData demo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('demo_data_test');
    township = TownshipStore();
    collection = CollectionStore();
    catDex = CatDexStore(storageDir: tmp);
    board = CommunityBoardStore(storageDir: tmp);
    demo = DemoData(
      township: township,
      collection: collection,
      catDex: catDex,
      board: board,
      includeMedia: false,
    );
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  BoardPost customPost() => BoardPost(
        id: 'custom-post-1',
        title: 'My own post',
        body: 'Written in-app, not part of any dataset.',
        category: 'Safety',
        precinct: 'Precinct A',
        authorLabel: 'Resident A-42',
        createdAt: DateTime.utc(2026, 10, 11, 12),
        isSynthetic: false,
      );

  group('seed', () {
    test('seed writes the four report states and board content', () async {
      final counts = await demo.seed();

      // 4 reports: 2 submitted, 1 in review, 1 resolved, across three precincts.
      expect(township.reports.length, 4);
      expect(
          township.reports.where((r) => r.status == 'submitted').length, 2);
      expect(township.triagedReports, 1);
      expect(township.resolvedReports, 1);
      expect(township.reports.map((r) => r.precinct).toSet(),
          {'Precinct 1', 'Precinct 2', 'Precinct 3'});

      // The four demo-script scenarios are on the board of reports.
      expect(
        township.reports.map((r) => r.category).toList(),
        containsAll(
            ['Illegal dumping', 'Street light out', 'Bin overflowing', 'Water pooling']),
      );

      // includeMedia:false skips every file-backed item entirely.
      expect(township.hubListings, isEmpty);
      expect(collection.entries, isEmpty);
      expect(catDex.sightings, isEmpty);
      expect(counts.hubListings, 0);
      expect(counts.collection, 0);
      expect(counts.cats, 0);
      expect(counts.reports, 4);

      // Board content: the synthetic seed plus the fixed demo post.
      final demoPost = board.byId(DemoData.demoBoardPostId);
      expect(demoPost, isNotNull);
      expect(demoPost!.isSynthetic, isTrue);
      expect(demoPost.title, isNotEmpty);
      expect(board.postCount, greaterThanOrEqualTo(9)); // 8 seed + 1 demo
      expect(counts.boardPosts, board.postCount);
    });

    test('seed is idempotent: a second load adds nothing', () async {
      await demo.seed();
      final reports = township.reports.length;
      final posts = board.postCount;

      final again = await demo.seed();
      expect(township.reports.length, reports);
      expect(board.postCount, posts);
      expect(again.reports, reports);
      expect(again.boardPosts, posts);
      expect(
          board.posts.where((p) => p.id == DemoData.demoBoardPostId).length, 1);
    });
  });

  group('reset', () {
    test('reset clears custom posts and demo content, then reseeds', () async {
      await demo.seed();
      // Resident-style content on top of the demo: a custom post and a
      // review pass over one of the demo reports.
      await board.addPost(customPost());
      township.triageReport(township.reports.first.id);
      expect(board.byId('custom-post-1'), isNotNull);
      expect(township.triagedReports, 2);

      final counts = await demo.reset();

      // The custom post is gone; the synthetic seed plus the fixed demo
      // post are back, all synthetic.
      expect(board.byId('custom-post-1'), isNull);
      expect(board.byId(DemoData.demoBoardPostId), isNotNull);
      expect(board.postCount, greaterThanOrEqualTo(9));
      for (final p in board.posts) {
        expect(p.isSynthetic, isTrue, reason: 'post ${p.id}');
      }

      // Demo content reseeded from clean: the four canonical states again.
      expect(counts.reports, 4);
      expect(township.reports.length, 4);
      expect(
          township.reports.where((r) => r.status == 'submitted').length, 2);
      expect(township.triagedReports, 1);
      expect(township.resolvedReports, 1);
      expect(counts.boardPosts, board.postCount);
    });

    test('clearDemoContent keeps onboarding, staff mode and taught refs',
        () async {
      await demo.seed();
      township.completeOnboarding('Ash', '12 Way Street', 'Precinct 2');
      township.setStaff(true);
      township.addTaughtRef(
          label: 'coffee cup', stream: 'Recyclable', photoPath: '');

      await township.clearDemoContent();

      expect(township.reports, isEmpty);
      expect(township.onboardingDone, isTrue);
      expect(township.householdName, 'Ash');
      expect(township.precinct, 'Precinct 2');
      expect(township.isStaff, isTrue);
      expect(township.taughtRefs.length, 1);
    });
  });

  group('demo photo hash', () {
    // The Go core's PHash is unusable (native panic on every input), so demo
    // entries carry DemoData.demoPhotoHash — this pins its contract.
    final photo = [for (var i = 0; i < 512; i++) i % 251];

    test('has the Go pHash output shape: 16 lowercase hex chars, stable',
        () {
      final h = DemoData.demoPhotoHash(photo);
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(h), isTrue,
          reason: 'got "$h"');
      expect(DemoData.demoPhotoHash(photo), h, reason: 'must be deterministic');
      expect(DemoData.demoPhotoHash([for (final b in photo) b ^ 0xFF]), isNot(h),
          reason: 'must be content-sensitive');
    });

    test('lets the collection log take a local hash without the Go core',
        () async {
      // Plain VM test: no MethodChannel would answer TownshipCore.pHashFile
      // here, so the seam is exactly what keeps the demo seed off the channel.
      final entry = await collection.add(
        itemLabel: 'cardboard box',
        category: WasteCategory.Reusable,
        confidence: 92,
        photoPath: '${tmp.path}/collection-box.png',
        photoHash: DemoData.demoPhotoHash(photo),
      );
      expect(entry.photoHash, DemoData.demoPhotoHash(photo));
      expect(collection.entries.length, 1);
      expect(entry.status, 'collected');
    });
  });
}
