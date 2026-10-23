/// Community board domain types: resident posts and their comments.
///
/// Hand-written `toJson`/`fromJson` in the same style as `lib/types.dart` —
/// `fromJson` tolerates missing optional keys so older files keep loading.
library;

/// The only categories a post may carry, in display order.
///
/// `BoardPost.category` is always one of these strings; the store seeds and the
/// compose sheet both read the list from here so the two can never drift.
const List<String> kBoardCategories = [
  'Safety',
  'Facilities',
  'Events',
  'Lost & Found',
  'Sustainability',
];

/// One comment on a [BoardPost].
class BoardComment {
  final String id;
  final String authorLabel;
  final String body;
  final DateTime createdAt;
  final bool isSynthetic;

  BoardComment({
    required this.id,
    required this.authorLabel,
    required this.body,
    required this.createdAt,
    this.isSynthetic = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'authorLabel': authorLabel,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
        'isSynthetic': isSynthetic,
      };

  static BoardComment fromJson(Map<String, dynamic> j) => BoardComment(
        id: j['id'] as String,
        authorLabel: (j['authorLabel'] ?? '') as String,
        body: (j['body'] ?? '') as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        isSynthetic: (j['isSynthetic'] ?? true) as bool,
      );
}

/// One resident post on the community board.
class BoardPost {
  final String id;
  final String title;
  final String body;

  /// One of [kBoardCategories].
  final String category;

  /// Precinct label only — never a street address.
  final String precinct;
  final String authorLabel;
  final DateTime createdAt;
  final int upvotes;
  final List<BoardComment> comments;

  /// True for the generated prototype seed; false for anything written in-app.
  final bool isSynthetic;

  BoardPost({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.precinct,
    required this.authorLabel,
    required this.createdAt,
    this.upvotes = 0,
    List<BoardComment>? comments,
    this.isSynthetic = true,
  }) : comments = comments ?? <BoardComment>[];

  int get commentCount => comments.length;

  /// Only the mutable-by-interaction fields are copyable; identity and author
  /// fields ride along unchanged.
  BoardPost copyWith({int? upvotes, List<BoardComment>? comments}) => BoardPost(
        id: id,
        title: title,
        body: body,
        category: category,
        precinct: precinct,
        authorLabel: authorLabel,
        createdAt: createdAt,
        upvotes: upvotes ?? this.upvotes,
        comments: comments ?? this.comments,
        isSynthetic: isSynthetic,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'category': category,
        'precinct': precinct,
        'authorLabel': authorLabel,
        'createdAt': createdAt.toIso8601String(),
        'upvotes': upvotes,
        'comments': [for (final c in comments) c.toJson()],
        'isSynthetic': isSynthetic,
      };

  static BoardPost fromJson(Map<String, dynamic> j) => BoardPost(
        id: j['id'] as String,
        title: (j['title'] ?? '') as String,
        body: (j['body'] ?? '') as String,
        category: (j['category'] ?? kBoardCategories.first) as String,
        precinct: (j['precinct'] ?? '') as String,
        authorLabel: (j['authorLabel'] ?? '') as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        upvotes: ((j['upvotes'] ?? 0) as num).toInt(),
        comments: [
          for (final c in (j['comments'] as List? ?? const <dynamic>[]))
            BoardComment.fromJson((c as Map).cast<String, dynamic>()),
        ],
        isSynthetic: (j['isSynthetic'] ?? true) as bool,
      );
}
