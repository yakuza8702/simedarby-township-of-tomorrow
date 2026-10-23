/// Cat Dex screen: the empty shelf (board-40 card + "Log a sighting" CTA),
/// the level banner, the sticker grid, one sheet per cat — plus the
/// persistent **'Log a sighting' app-bar action** this screen contributes
/// into the host app bar whenever the Dex shows at least one sighting.
///
/// Reads the Dex store and writes to the community board through its public
/// API only (`addPost`) — the Dex owns no board code of its own. Sharing is
/// idempotent by the deterministic post id `cat-dex-<sightingId>` (the board's
/// WO-02 contract: `addPost` dedupes by id), so pressing share twice adds one
/// post and says so. Both stores are injected (with the app singletons as the
/// default) so widget tests can run without platform channels.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../community_board/board_models.dart';
import '../community_board/board_store.dart';
import '../main.dart' show App;
import '../theme.dart';
import 'cat_dex_models.dart';
import 'cat_dex_store.dart';
import 'log_sighting_screen.dart';

/// The board post a shared sighting becomes — deterministic id so sharing the
/// same sighting twice stays one post.
///
/// Precinct label only — never a street address, never a person's name — and
/// `isSynthetic: false` because a resident really did press the button.
BoardPost catDexBoardPost(CatSighting sighting, {required String authorLabel}) =>
    BoardPost(
      id: catDexPostId(sighting),
      title: 'Cat Distribution System: a cat was assigned at ${sighting.precinct}',
      body: '"${sighting.name}" now lives with a resident of '
          '${sighting.precinct}. Species confirmed: cat. '
          'Paperwork: none required.',
      category: 'Lost & Found',
      precinct: sighting.precinct,
      authorLabel: authorLabel,
      createdAt: DateTime.now(),
      isSynthetic: false,
    );

/// The deterministic board-post id for [sighting] (`cat-dex-<sightingId>`).
String catDexPostId(CatSighting sighting) => 'cat-dex-${sighting.id}';

/// Whether [sighting] has already been shared to [board] (one post per id).
bool catDexAlreadyShared(CommunityBoardStore board, CatSighting sighting) =>
    board.byId(catDexPostId(sighting)) != null;

/// Anonymous board label in the same style as the board's own compose sheet.
String catDexAuthorLabel(CommunityBoardStore board) =>
    'Resident A-${(board.postCount + 1).toString().padLeft(2, '0')}';

/// Publish [sighting] to [board]; returns the stored post.
///
/// Idempotent by [catDexPostId]: a sighting that is already on the board is
/// returned untouched instead of posted again.
Future<BoardPost> shareSightingToBoard({
  required CommunityBoardStore board,
  required CatSighting sighting,
  String? authorLabel,
}) async {
  final existing = board.byId(catDexPostId(sighting));
  if (existing != null) return existing;
  return board.addPost(catDexBoardPost(
    sighting,
    authorLabel: authorLabel ?? catDexAuthorLabel(board),
  ));
}

/// The level banner's headline: `Cat Level <index>`, e.g. `Cat Level 2` at
/// three cats under the `[0, 1, 3, 4, 10]` thresholds.
String catDexLevelLabel(CatDexStore store) => 'Cat Level ${store.levelIndex}';

/// The banner's tier-progress line: how many more cats unlock the next tier,
/// singular at exactly one, and the max-tier salute once topped out.
String catDexTierLine(CatDexStore store) {
  final remaining = store.catsToNextLevel;
  if (remaining == null) {
    return 'Maximum tier reached. The cats are pleased.';
  }
  return remaining == 1
      ? '1 cat unlocks the next tier'
      : '$remaining cats unlock the next tier';
}

class CatDexScreen extends StatefulWidget {
  final CatDexStore store;

  /// `null` → the app singleton; injected in tests.
  final CommunityBoardStore? board;

  const CatDexScreen({super.key, required this.store, this.board});

  @override
  State<CatDexScreen> createState() => _CatDexScreenState();
}

class _CatDexScreenState extends State<CatDexScreen> {
  /// The 'Log a sighting' action, anchored into the HOST app bar through a
  /// single overlay entry.
  ///
  /// The `/cat-dex` route (main.dart) owns this screen's Scaffold + AppBar —
  /// the same wrapper pattern its other pushed routes use — so the action is
  /// contributed from here into that bar's action slot instead of stacking a
  /// second toolbar under it. Recipe mirrors main.dart's app-bar actions:
  /// 48dp target (>= the 44dp floor), tooltip + Semantics label
  /// 'Log a sighting', icon button. No visible Text, so the empty-shelf CTA
  /// stays the only text-labelled button.
  OverlayEntry? _barAction;

  /// The host route's animation; a status tick rebuilds the entry so the
  /// action appears exactly when the route settles and never mid-transition.
  Animation<double>? _routeAnimation;

  CatDexStore get store => widget.store;

  CommunityBoardStore get _board => widget.board ?? App.instance.board;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_syncBarAction);
    // First paint decides whether the host even has an app bar to join.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncBarAction());
  }

  @override
  void dispose() {
    widget.store.removeListener(_syncBarAction);
    _routeAnimation?.removeListener(_markBarAction);
    final entry = _barAction;
    _barAction = null;
    if (entry != null) {
      entry
        ..remove()
        ..dispose();
    }
    super.dispose();
  }

  /// The host scaffold really carries an app bar (production) — a bare
  /// `Scaffold(body: ...)` test harness has none, so those tests see no
  /// action at all.
  bool get _hostHasAppBar => Scaffold.maybeOf(context)?.widget.appBar != null;

  /// Insert / drop the action as the Dex crosses the 0/1-sightings line,
  /// then nudge a rebuild. Store notifications can land while the framework
  /// is building, so the rebuild is deferred out of the build phase.
  void _syncBarAction() {
    if (!mounted) return;
    final wantsAction = store.count > 0 && _hostHasAppBar;
    if (wantsAction && _barAction == null) {
      final overlay = Overlay.maybeOf(context);
      if (overlay == null) return;
      final entry = OverlayEntry(builder: _buildBarAction);
      _barAction = entry;
      overlay.insert(entry);
      _routeAnimation ??= ModalRoute.of(context)?.animation;
      _routeAnimation?.addListener(_markBarAction);
    } else if (!wantsAction && _barAction != null) {
      final entry = _barAction!;
      _barAction = null;
      entry
        ..remove()
        ..dispose();
    }
    _markBarAction();
  }

  void _markBarAction() {
    final entry = _barAction;
    if (entry == null) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _barAction?.markNeedsBuild();
      });
    } else {
      entry.markNeedsBuild();
    }
  }

  /// The app-bar action itself. The entry floats above every route, so it
  /// only renders while THIS screen's route is current and fully settled;
  /// any pushed sheet/route swaps it out instead of being covered by it.
  ///
  /// Position: the host AppBar is the screen's top edge (its SafeArea eats
  /// the status inset), its toolbar is the bottom [kToolbarHeight] of that
  /// band, and AppBar actions sit flush to the trailing edge
  /// (`actionsPadding: EdgeInsets.zero`) — so the 48dp button centers in the
  /// toolbar exactly where a real `actions:` entry would land.
  Widget _buildBarAction(BuildContext overlayContext) {
    if (!mounted || store.count == 0 || !_hostHasAppBar) {
      return const SizedBox.shrink();
    }
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return const SizedBox.shrink();
    final animation = route.animation;
    if (animation != null && animation.status != AnimationStatus.completed) {
      return const SizedBox.shrink();
    }
    const actionSize = 48.0; // main.dart's app-bar buttons use the same 48dp.
    final topPadding = MediaQuery.of(overlayContext).padding.top;
    return Positioned(
      right: 0,
      top: topPadding + (kToolbarHeight - actionSize) / 2,
      width: actionSize,
      height: actionSize,
      child: Semantics(
        button: true,
        label: 'Log a sighting',
        child: IconButton(
          tooltip: 'Log a sighting',
          constraints: const BoxConstraints(
              minWidth: actionSize, minHeight: actionSize),
          color: Theme.of(overlayContext).colorScheme.onSurface,
          icon: const Icon(Icons.add_a_photo_outlined),
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: (_) => const LogSightingScreen()),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // No cats yet → no level banner, just the empty shelf card.
          if (store.count > 0) ...[
            _banner(context),
            const SizedBox(height: 14),
            Text('Caught so far · newest first',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _grid(context),
          ] else
            _emptyState(context),
        ],
      ),
    );
  }

  Widget _banner(BuildContext context) {
    return Card(
      color: context.tTintGreen,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.pets, color: context.tBrand),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(catDexLevelLabel(store),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                        '${store.count} '
                        '${store.count == 1 ? "cat" : "cats"} assigned · '
                        'Cat Distribution System',
                        style: TextStyle(
                            fontSize: 12, color: context.tMuted)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: store.levelProgress,
              backgroundColor: context.tTrack,
              color: context.tBrand,
            ),
            const SizedBox(height: 6),
            Text(catDexTierLine(store),
                style: TextStyle(fontSize: 11, color: context.tMuted)),
          ],
        ),
      ),
    );
  }

  /// Board-40 style empty shelf: quiet copy, then the log-a-sighting CTA that
  /// pushes [LogSightingScreen].
  Widget _emptyState(BuildContext context) {
    return Card(
      color: context.tTintGreen,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.visibility_outlined, color: context.tBrand, size: 36),
            const SizedBox(height: 10),
            Text('The Dex is quiet',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
                'Spot a stray cat on a scan run? Log the sighting to fill this '
                'shelf.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: context.tMuted)),
            const SizedBox(height: 14),
            Semantics(
              button: true,
              label: 'Log a sighting',
              child: FilledButton.icon(
                icon: const Icon(Icons.add_a_photo_outlined),
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48)),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const LogSightingScreen()),
                ),
                label: const Text('Log a sighting'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid(BuildContext context) {
    final cats = store.sightings;
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.82,
      children: [
        for (final s in cats) _tile(context, s),
      ],
    );
  }

  Widget _tile(BuildContext context, CatSighting s) {
    return Card(
      child: InkWell(
        key: ValueKey('cat-sticker-${s.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetail(context, s),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            children: [
              Expanded(child: _sticker(s)),
              const SizedBox(height: 4),
              Text(s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sticker(CatSighting s, {double? size}) => Image.file(
        File(s.stickerPath),
        width: size,
        height: size,
        fit: BoxFit.contain,
        // A cleared cache must not take the whole Dex down with it.
        errorBuilder: (context, error, stack) =>
            Icon(Icons.pets, color: context.tBrand),
      );

  Future<void> _openDetail(BuildContext context, CatSighting s) async {
    final boardStore = _board;
    final messenger = ScaffoldMessenger.maybeOf(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _SightingSheet(
        sighting: s,
        preview: _sticker(s, size: 96),
        onShare: () async {
          final alreadyShared = catDexAlreadyShared(boardStore, s);
          await shareSightingToBoard(board: boardStore, sighting: s);
          if (!sheetContext.mounted) return;
          Navigator.of(sheetContext).pop();
          messenger?.showSnackBar(SnackBar(
              content: Text(alreadyShared
                  ? 'Already shared to the community board'
                  : 'Sighting shared to the community board')));
          if (!context.mounted) return;
          // Share leaves for the board either way — repeat share just says so.
          Navigator.of(context).pushNamed('/board');
        },
      ),
    );
  }
}

class _SightingSheet extends StatelessWidget {
  final CatSighting sighting;
  final Widget preview;
  final Future<void> Function() onShare;

  const _SightingSheet({
    required this.sighting,
    required this.preview,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              preview,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sighting.name,
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                        '${_stamp(sighting.capturedAt)} · '
                        '${sighting.precinct}',
                        style: TextStyle(
                            fontSize: 12, color: context.tMuted)),
                    const SizedBox(height: 4),
                    Text(
                        'Caught via ${sighting.source} · '
                        '${sighting.displayItemLabel}',
                        style: TextStyle(
                            fontSize: 12, color: context.tMuted)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 14),
            const Text(
                'Assigned by the Cat Distribution System. There is nothing '
                'else for you to do.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: Semantics(
                button: true,
                label: 'Share sighting to board',
                child: FilledButton.icon(
                  icon: const Icon(Icons.campaign_outlined),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: onShare,
                  label: const Text('Share sighting to board'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// `YYYY-MM-DD HH:MM` — no `intl` dependency, no locale surprises.
  static String _stamp(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }
}
