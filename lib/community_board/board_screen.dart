/// Community Board screen — resident posts, comments, votes.
///
/// Offline only: everything lives in [CommunityBoardStore] on this device, no
/// network calls. The top banner is pinned for the whole screen because the seed
/// is synthetic — see `synthetic_seed.dart`.
library;

import 'package:flutter/material.dart';

import 'board_models.dart';
import 'board_store.dart';
import '../theme.dart';

/// Accent shared with the rest of the app: the seed green through the
/// active theme (exact #2E7D32 in light, the lifted seed in dark).
Color _accent(BuildContext context) => context.tScheme.primary;

const String kSyntheticBannerText =
    'Synthetic demo data — generated for this prototype, not real resident data';

class CommunityBoardScreen extends StatefulWidget {
  final CommunityBoardStore store;

  const CommunityBoardScreen({super.key, required this.store});

  @override
  State<CommunityBoardScreen> createState() => _CommunityBoardScreenState();
}

class _CommunityBoardScreenState extends State<CommunityBoardScreen> {
  final TextEditingController _search = TextEditingController();

  /// `null` = the "All" chip.
  String? _category;

  @override
  void initState() {
    super.initState();
    // Idempotent: a pre-loaded store just re-reads the same file.
    widget.store.load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<BoardPost> _visible() {
    final q = _search.text.trim();
    final base = q.isEmpty ? widget.store.posts : widget.store.search(q);
    if (_category == null) return base;
    return [for (final p in base) if (p.category == _category) p];
  }

  /// Demo authors are synthetic labels; posts written in-app are marked
  /// `isSynthetic: false` so the banner never claims them as generated data.
  String get _demoAuthorLabel =>
      'Resident A-${(widget.store.postCount + 1).toString().padLeft(2, '0')}';

  Future<void> _openPost(BoardPost post) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PostDetailPage(store: widget.store, postId: post.id),
      ),
    );
  }

  Future<void> _composePost() async {
    final post = await showModalBottomSheet<BoardPost>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ComposeSheet(authorLabel: _demoAuthorLabel),
    );
    if (post == null) return;
    await widget.store.addPost(post);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Posted to the community board')),
    );
  }

  /// Board-39 empty variant: nothing on the board yet.
  Widget _emptyBoard(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: context.tHairline),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.forum_outlined,
                      size: 44, color: context.tGhost),
                  const SizedBox(height: 12),
                  Text(
                    'No posters around you yet',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'See something the neighbourhood should know? Start the '
                    'first post.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: context.tMuted),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            backgroundColor: _accent(context)),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Write the first post'),
                        onPressed: _composePost,
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 44)),
                        onPressed: _showRules,
                        child: const Text('Browse rules'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  /// Board-39 filtered-empty variant: the board has posts, this filter hides
  /// them all — offer a one-tap reset instead of a dead end.
  Widget _filteredEmpty(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.filter_alt_off_outlined,
                  size: 40, color: context.tGhost),
              const SizedBox(height: 12),
              Text(
                'Nothing matches this filter',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text('Clear all'),
                onPressed: () => setState(() {
                  _search.clear();
                  _category = null;
                }),
              ),
            ],
          ),
        ),
      );

  /// Local rules sheet — no network, plain guidance text. Scrollable so the
  /// content survives short viewports instead of overflowing.
  Future<void> _showRules() => showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Community board rules',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                const Text(
                  '· Keep posts about this township — hazards belong in '
                  '"Report a problem" so operators can act on them.\n'
                  '· Location talk stays at precinct level: no street '
                  'addresses, phone numbers or emails.\n'
                  '· Seed posts are synthetic demo data; anything you write is '
                  'marked resident-written.\n'
                  '· Say what, where (precinct) and what would help — specific '
                  'and kind gets results.',
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        backgroundColor: _accent(context)),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Got it'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final posts = _visible();
        return Stack(
          children: [
            Column(
              children: [
                _banner(),
                _searchRow(),
                _filterChips(),
                const Divider(height: 1),
                Expanded(
                  child: widget.store.posts.isEmpty
                      // Board-39: no posts at all — invite the first one.
                      ? _emptyBoard(context)
                      : posts.isEmpty
                          // Board-39: posts exist, the active filter hides them.
                          ? _filteredEmpty(context)
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                              itemCount: posts.length,
                              itemBuilder: (context, i) =>
                                  _postCard(context, posts[i]),
                            ),
                ),
              ],
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                onPressed: _composePost,
                backgroundColor: _accent(context),
                foregroundColor: context.tScheme.onPrimary,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('New post'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _banner() => Container(
        width: double.infinity,
        // Cream callout wash: the dark theme swaps in the dark amber wash,
        // the amber accent / muted pair flips with it.
        color: context.tAmberWash,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.science_outlined,
                size: 18, color: context.tAmberAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                kSyntheticBannerText,
                style: TextStyle(fontSize: 12, color: context.tAmberMuted),
              ),
            ),
          ],
        ),
      );

  Widget _searchRow() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search posts',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(_search.clear),
                  ),
            border: const OutlineInputBorder(),
          ),
        ),
      );

  Widget _filterChips() => SizedBox(
        height: 44,
        // Horizontal SingleChildScrollView (not a ListView): every chip is laid
        // out at its intrinsic width and stays in the tree, so all six remain
        // reachable on narrow screens instead of being clipped off the edge of
        // a non-scrollable row.
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: const Text('All'),
                  selected: _category == null,
                  onSelected: (_) => setState(() => _category = null),
                ),
              ),
              for (final c in kBoardCategories)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(c),
                    selected: _category == c,
                    onSelected: (_) => setState(() => _category = c),
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _postCard(BuildContext context, BoardPost post) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openPost(post),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      post.title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (post.isSynthetic)
                    Tooltip(
                      message: 'Sample post — demo data',
                      child: Icon(Icons.science_outlined,
                          size: 14, color: context.tAmberAccent),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _categoryChip(post.category),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${post.precinct} · ${post.authorLabel}',
                      style:
                          TextStyle(fontSize: 11, color: context.tMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _upvoteButton(post),
                  const SizedBox(width: 12),
                  Icon(Icons.mode_comment_outlined,
                      size: 16, color: context.tMuted),
                  const SizedBox(width: 4),
                  Text('${post.commentCount}',
                      style: TextStyle(fontSize: 12, color: context.tMuted)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _categoryChip(String category) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: context.tTintGreen,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          category,
          style: TextStyle(fontSize: 11, color: context.tBrand),
        ),
      );

  Widget _upvoteButton(BoardPost post) => OutlinedButton.icon(
        onPressed: () => widget.store.upvote(post.id),
        icon: const Icon(Icons.arrow_upward, size: 14),
        label: Text('${post.upvotes}'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          visualDensity: VisualDensity.compact,
        ),
      );
}

/// Post detail: body, comments, compose field, upvote.
class _PostDetailPage extends StatefulWidget {
  final CommunityBoardStore store;
  final String postId;

  const _PostDetailPage({required this.store, required this.postId});

  @override
  State<_PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<_PostDetailPage> {
  final TextEditingController _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  String get _demoAuthorLabel =>
      'Resident A-${(widget.store.postCount + 1).toString().padLeft(2, '0')}';

  Future<void> _submitComment(String postId) async {
    final text = _comment.text.trim();
    if (text.isEmpty) return;
    await widget.store.addComment(
      postId,
      BoardComment(
        id: 'c-${DateTime.now().microsecondsSinceEpoch}',
        authorLabel: _demoAuthorLabel,
        body: text,
        createdAt: DateTime.now(),
        isSynthetic: false,
      ),
    );
    _comment.clear();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Community Board')),
      body: AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final post = widget.store.byId(widget.postId);
          if (post == null) {
            return const Center(child: Text('This post is no longer available.'));
          }
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _header(context, post),
                    const SizedBox(height: 12),
                    Text(post.body, style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => widget.store.upvote(post.id),
                          icon: const Icon(Icons.arrow_upward, size: 16),
                          label: Text('Upvote (${post.upvotes})'),
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    Text('Comments (${post.commentCount})',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    if (post.comments.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('No comments yet — be the first.',
                            style:
                                TextStyle(fontSize: 12, color: context.tMuted)),
                      ),
                    for (final c in post.comments) _commentTile(c),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _comment,
                          minLines: 1,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'Add a comment',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Send comment',
                        onPressed: () => _submitComment(post.id),
                        icon: Icon(Icons.send, color: _accent(context)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context, BoardPost post) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(post.title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            '${post.category} · ${post.precinct} · ${post.authorLabel}'
            '${post.isSynthetic ? ' · synthetic' : ''}',
            style: TextStyle(fontSize: 11, color: context.tMuted),
          ),
        ],
      );

  Widget _commentTile(BoardComment c) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${c.authorLabel}${c.isSynthetic ? ' · synthetic' : ''}',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.tMuted),
            ),
            const SizedBox(height: 2),
            Text(c.body, style: const TextStyle(fontSize: 13)),
          ],
        ),
      );
}

/// Compose sheet: pops with the [BoardPost] to add, or `null` on cancel.
class _ComposeSheet extends StatefulWidget {
  final String authorLabel;

  const _ComposeSheet({required this.authorLabel});

  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  String _category = kBoardCategories.first;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty || body.isEmpty) return;
    Navigator.of(context).pop(
      BoardPost(
        id: 'p-${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        body: body,
        category: _category,
        precinct: 'Precinct A',
        authorLabel: widget.authorLabel,
        createdAt: DateTime.now(),
        // Written in-app, not generated: the banner must not claim it.
        isSynthetic: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New post',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Stored on this device. Your post is marked as resident-written, '
              'not synthetic.',
              style: TextStyle(fontSize: 11, color: context.tMuted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _body,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Details',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final c in kBoardCategories)
                  DropdownMenuItem<String>(value: c, child: Text(c)),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _category = v);
              },
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                      backgroundColor: _accent(context)),
                  child: const Text('Post'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
