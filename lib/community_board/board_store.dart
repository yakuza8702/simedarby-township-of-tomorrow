/// Community board state: resident posts and comments on this device.
///
/// Follows the hand-rolled persistence pattern of `lib/store/collection_store.dart`:
/// a single JSON file in the app documents dir, written whole on every change.
/// The directory is injectable so unit tests can point at a temp dir instead of
/// the `path_provider` plugin (which is unavailable in a plain VM test).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'board_models.dart';
import 'synthetic_seed.dart';

class CommunityBoardStore extends ChangeNotifier {
  /// [storageDir] `null` (the app default) → `getApplicationDocumentsDirectory()`.
  CommunityBoardStore({this._storageDir});

  static const fileName = 'community_board.json';

  final Directory? _storageDir;
  final List<BoardPost> _posts = [];
  File? _file;
  bool _loaded = false;

  List<BoardPost> get posts => List.unmodifiable(_posts);
  bool get loaded => _loaded;
  int get postCount => _posts.length;
  int get commentCount => _posts.fold(0, (s, p) => s + p.comments.length);

  BoardPost? byId(String id) {
    for (final p in _posts) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Read `community_board.json`; with no file yet, seed from the synthetic
  /// dataset and write it out so the first run is indistinguishable afterwards.
  Future<void> load() async {
    final dir = _storageDir ?? await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/$fileName');
    if (await _file!.exists()) {
      try {
        final list = (jsonDecode(await _file!.readAsString()) as List)
            .cast<Map<String, dynamic>>();
        _posts
          ..clear()
          ..addAll([for (final j in list) BoardPost.fromJson(j)]);
      } catch (e) {
        debugPrint('TWP:ERROR board load: $e');
      }
    } else {
      _posts
        ..clear()
        ..addAll([for (final j in kSyntheticBoardSeed) BoardPost.fromJson(j)]);
      await save();
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> save() async {
    if (_file == null) return;
    await _file!.writeAsString(jsonEncode([for (final p in _posts) p.toJson()]));
  }

  /// Newest post first, matching the collection log's insertion order.
  ///
  /// Idempotent by [BoardPost.id]: a post whose id is already on the board is
  /// returned exactly as stored — no duplicate insert, no save. Retryable
  /// flows (report-resolution shares, cat-dex sightings) can call this again
  /// after a crash or a double-tap without ever double-posting.
  Future<BoardPost> addPost(BoardPost post) async {
    final existing = byId(post.id);
    if (existing != null) return existing;
    _posts.insert(0, post);
    await save();
    notifyListeners();
    return post;
  }

  /// Replace whatever is on the board with the synthetic seed dataset.
  Future<void> resetToSeed() async {
    _posts
      ..clear()
      ..addAll([for (final j in kSyntheticBoardSeed) BoardPost.fromJson(j)]);
    await save();
    notifyListeners();
  }

  /// Remove every post, leaving the board empty.
  Future<void> clearAll() async {
    _posts.clear();
    await save();
    notifyListeners();
  }

  /// Returns the added comment, or `null` when [postId] is unknown.
  Future<BoardComment?> addComment(String postId, BoardComment comment) async {
    final idx = _posts.indexWhere((p) => p.id == postId);
    if (idx < 0) return null;
    final post = _posts[idx];
    _posts[idx] = post.copyWith(comments: [...post.comments, comment]);
    await save();
    notifyListeners();
    return comment;
  }

  /// Returns the updated post, or `null` when [postId] is unknown.
  Future<BoardPost?> upvote(String postId) async {
    final idx = _posts.indexWhere((p) => p.id == postId);
    if (idx < 0) return null;
    final post = _posts[idx];
    _posts[idx] = post.copyWith(upvotes: post.upvotes + 1);
    await save();
    notifyListeners();
    return _posts[idx];
  }

  /// `null` category → every post (the "All" chip).
  List<BoardPost> byCategory(String? category) => category == null
      ? posts
      : [for (final p in _posts) if (p.category == category) p];

  /// Case-insensitive match on title or body; a blank query returns everything.
  List<BoardPost> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return posts;
    return [
      for (final p in _posts)
        if (p.title.toLowerCase().contains(q) ||
            p.body.toLowerCase().contains(q))
          p,
    ];
  }
}
