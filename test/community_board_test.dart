/// Unit tests for the Community Board: JSON round-trips, store behaviour
/// (add / comment / upvote / filter / search) and the synthetic seed contract.
///
/// The seed is the only content the prototype ships with, so its integrity is
/// pinned here: every entry `isSynthetic: true`, both precincts, all five
/// categories, ≥8 posts and ≥15 comments, and no real-world contact details.
///
/// The store takes an injectable storage directory, so these tests never touch
/// `path_provider` (unavailable in a plain VM test) and never write to the real
/// documents dir.
///
/// Run: `flutter test test/community_board_test.dart`
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:township_of_tomorrow/community_board/board_models.dart';
import 'package:township_of_tomorrow/community_board/board_store.dart';
import 'package:township_of_tomorrow/community_board/synthetic_seed.dart';

BoardComment _comment(String id, String body) => BoardComment(
      id: id,
      authorLabel: 'Resident A-42',
      body: body,
      createdAt: DateTime.utc(2026, 10, 1, 9, 30),
      isSynthetic: false,
    );

BoardPost _post(String id, {String category = 'Safety'}) => BoardPost(
      id: id,
      title: 'Test post $id',
      body: 'Body for $id',
      category: category,
      precinct: 'Precinct A',
      authorLabel: 'Resident A-42',
      createdAt: DateTime.utc(2026, 10, 2, 8),
      isSynthetic: false,
    );

void main() {
  late Directory tmp;
  late CommunityBoardStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('board_test');
    store = CommunityBoardStore(storageDir: tmp);
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  File boardFile() => File('${tmp.path}/${CommunityBoardStore.fileName}');

  group('models', () {
    test('BoardComment JSON round-trip', () {
      final original = BoardComment(
        id: 'c-1',
        authorLabel: 'Resident B-07',
        body: 'Chain is frayed on the left bay.',
        createdAt: DateTime.utc(2026, 9, 26, 16, 30),
        isSynthetic: true,
      );
      final decoded = BoardComment.fromJson(
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>);

      expect(decoded.id, original.id);
      expect(decoded.authorLabel, original.authorLabel);
      expect(decoded.body, original.body);
      expect(decoded.createdAt, original.createdAt);
      expect(decoded.isSynthetic, isTrue);
    });

    test('BoardPost JSON round-trip keeps comments and flags', () {
      final original = _post('p-1')
        ..comments.add(_comment('c-1', 'first'))
        ..comments.add(_comment('c-2', 'second'));
      final withUpvotes = original.copyWith(upvotes: 5);

      final decoded = BoardPost.fromJson(
          jsonDecode(jsonEncode(withUpvotes.toJson())) as Map<String, dynamic>);

      expect(decoded.id, 'p-1');
      expect(decoded.title, withUpvotes.title);
      expect(decoded.body, withUpvotes.body);
      expect(decoded.category, 'Safety');
      expect(decoded.precinct, 'Precinct A');
      expect(decoded.authorLabel, 'Resident A-42');
      expect(decoded.createdAt, withUpvotes.createdAt);
      expect(decoded.upvotes, 5);
      expect(decoded.isSynthetic, isFalse);
      expect(decoded.comments.length, 2);
      expect(decoded.comments[1].body, 'second');
      expect(decoded.comments[0].isSynthetic, isFalse);
    });

    test('category list is exactly the five allowed values', () {
      expect(kBoardCategories, const [
        'Safety',
        'Facilities',
        'Events',
        'Lost & Found',
        'Sustainability',
      ]);
      for (final j in kSyntheticBoardSeed) {
        expect(kBoardCategories, contains(j['category']));
      }
    });

    test('fromJson tolerates missing optional keys', () {
      final decoded = BoardPost.fromJson(<String, dynamic>{
        'id': 'p-legacy',
        'createdAt': '2026-10-01T00:00:00.000Z',
      });
      expect(decoded.title, '');
      expect(decoded.upvotes, 0);
      expect(decoded.comments, isEmpty);
      expect(decoded.category, kBoardCategories.first);
    });
  });

  group('synthetic seed', () {
    test('load() with no file seeds, saves, and writes the file', () async {
      expect(boardFile().existsSync(), isFalse);
      await store.load();

      expect(boardFile().existsSync(), isTrue);
      expect(store.loaded, isTrue);
      expect(store.posts.length, greaterThanOrEqualTo(8));
      expect(store.commentCount, greaterThanOrEqualTo(15));
      expect(store.posts.first.isSynthetic, isTrue);
    });

    test('every seed entry and comment is flagged synthetic', () async {
      await store.load();
      for (final p in store.posts) {
        expect(p.isSynthetic, isTrue, reason: 'post ${p.id}');
        for (final c in p.comments) {
          expect(c.isSynthetic, isTrue, reason: 'comment ${c.id}');
        }
      }
      for (final j in kSyntheticBoardSeed) {
        expect(j['isSynthetic'], isTrue);
        for (final c in (j['comments'] as List).cast<Map<String, dynamic>>()) {
          expect(c['isSynthetic'], isTrue);
        }
      }
    });

    test('seed covers all 5 categories and both precincts', () async {
      await store.load();
      expect(store.posts.map((p) => p.category).toSet(),
          containsAll(kBoardCategories));
      expect(store.posts.map((p) => p.precinct).toSet(),
          containsAll(const ['Precinct A', 'Precinct B']));
    });

    test('seed carries no emails, URLs or phone numbers', () {
      final blob = jsonEncode(kSyntheticBoardSeed);
      expect(blob.contains('@'), isFalse);
      expect(blob.toLowerCase().contains('http'), isFalse);
      expect(RegExp(r'\b0[0-9]{9}\b').hasMatch(blob), isFalse);
    });
  });

  group('store behaviour', () {
    test('addPost puts the newest post first and persists it', () async {
      await store.load();
      final seeded = store.posts.length;

      await store.addPost(_post('p-user-1', category: 'Events'));
      expect(store.postCount, seeded + 1);
      expect(store.posts.first.id, 'p-user-1');
      expect(store.posts.first.isSynthetic, isFalse);

      final reopen = CommunityBoardStore(storageDir: tmp);
      await reopen.load();
      expect(reopen.posts.first.id, 'p-user-1');
      expect(reopen.posts.length, seeded + 1);
      expect(reopen.posts.first.isSynthetic, isFalse);
    });

    test('addComment appends to the right post only', () async {
      await store.load();
      final target = store.posts[1];
      final before = store.posts[0].commentCount;

      final added = await store.addComment(target.id, _comment('c-user-1', 'hi'));
      expect(added, isNotNull);
      expect(store.byId(target.id)!.commentCount, target.commentCount + 1);
      expect(store.byId(target.id)!.comments.last.body, 'hi');
      expect(store.posts[0].commentCount, before);

      expect(await store.addComment('missing-id', _comment('c-x', 'x')), isNull);
    });

    test('upvote increments one post and survives a reload', () async {
      await store.load();
      final target = store.posts[2];
      final other = store.posts[3];
      final othersBefore = other.upvotes;

      final bumped = await store.upvote(target.id);
      expect(bumped!.upvotes, target.upvotes + 1);
      expect(store.byId(other.id)!.upvotes, othersBefore);
      expect(await store.upvote('missing-id'), isNull);

      final reopen = CommunityBoardStore(storageDir: tmp);
      await reopen.load();
      expect(reopen.byId(target.id)!.upvotes, target.upvotes + 1);
    });

    test('byCategory filters, null returns every post', () async {
      await store.load();
      final all = store.byCategory(null);
      expect(all.length, store.postCount);
      for (final c in kBoardCategories) {
        final filtered = store.byCategory(c);
        expect(filtered, isNotEmpty, reason: c);
        expect(filtered.every((p) => p.category == c), isTrue);
      }
      expect(store.byCategory('Nonexistent'), isEmpty);
    });

    test('search matches title and body case-insensitively', () async {
      await store.load();
      expect(store.search('').length, store.postCount);
      expect(store.search('   ').length, store.postCount);

      final hit = store.posts.first;
      final upper = hit.title.toUpperCase();
      expect(store.search(upper).map((p) => p.id), contains(hit.id));

      final bodyWord = hit.body.split(' ').first;
      expect(store.search(bodyWord.toLowerCase()).map((p) => p.id),
          contains(hit.id));

      expect(store.search('zzz-no-such-post-zzz'), isEmpty);
    });

    test('corrupt file does not throw and leaves the store empty', () async {
      await boardFile().writeAsString('{not json');
      await store.load();
      expect(store.posts, isEmpty);
      expect(store.loaded, isTrue);
    });
  });
}
