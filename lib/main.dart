import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cat_dex/cat_dex_screen.dart';
import 'cat_dex/cat_dex_store.dart';
import 'community_board/board_screen.dart';
import 'community_board/board_store.dart';
import 'screens/collection_screen.dart';
import 'screens/command_center_screen.dart';
import 'screens/home_screen.dart';
import 'screens/hub_screen.dart';
import 'screens/map_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/operator_dashboard.dart';
import 'screens/profile_screen.dart';
import 'screens/report_screen.dart';
import 'screens/scan_screen.dart' show ScanScreen, scanStateHandler;
import 'screens/splash_screen.dart';
import 'screens/teach_scanner_screen.dart';
import 'screens/tour_overlay.dart';
import 'services/reference_library.dart';
import 'services/text_recognition.dart';
import 'services/township_core.dart';
import 'services/vision_pipeline.dart';
import 'store/collection_store.dart';
import 'store/township_store.dart';
import 'theme.dart';

/// Township of Tomorrow — Flutter + Go rebuild, full legacy surface.
/// Bottom nav: Home · Scan · Collection · Circular Hub · Map, Profile in the
/// app bar; staff tier at /operator, council tier at /command.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TownshipApp());
}

class TownshipApp extends StatefulWidget {
  const TownshipApp({super.key});

  @override
  State<TownshipApp> createState() => _TownshipAppState();
}

class _TownshipAppState extends State<TownshipApp> {
  @override
  Widget build(BuildContext context) {
    // The appearance setting lives in the township store (same JSON file as
    // every other preference), so the whole app rebuilds when it flips.
    return AnimatedBuilder(
      animation: App.instance.township,
      builder: (context, _) {
        final mode = themeModeFromSetting(App.instance.township.themeMode);
        return MaterialApp(
          title: 'Township of Tomorrow',
          theme: buildTownshipTheme(),
          darkTheme: buildTownshipTheme(brightness: Brightness.dark),
          themeMode: mode,
          routes: {
            '/scan': (_) => const _ScanRoute(),
            '/collection': (_) => const _CollectionRoute(),
            '/hub': (_) => const _HubRoute(),
            '/map': (_) => const _MapRoute(),
            '/profile': (_) => const _ProfileRoute(),
            '/operator': (_) => const _OperatorRoute(),
            '/command': (_) => const _CommandRoute(),
            '/report': (_) => const _ReportRoute(),
            '/board': (_) => const _BoardRoute(),
            '/teach': (_) => const _TeachRoute(),
            '/cat-dex': (_) => const _CatDexRoute(),
          },
          home: const Root(),
        );
      },
    );
  }
}

/// Shared app scope so heavy models load exactly once for every route.
class App extends ChangeNotifier {
  static final App instance = App();
  final VisionPipeline pipeline = VisionPipeline();
  final CollectionStore collection = CollectionStore();
  final TownshipStore township = TownshipStore();
  final CommunityBoardStore board = CommunityBoardStore();
  final CatDexStore catDex = CatDexStore();
  final TextRecognitionService ocr = TextRecognitionService();
  final CollectionStats stats = CollectionStats();
  ReferenceLibrary? _refs;
  bool booted = false;
  String coreVersion = '';
  bool aiReady = false;

  ReferenceLibrary get refs => _refs ??= ReferenceLibrary(pipeline.embedder, township);

  static String? pendingDebugImport;

  static Map<String, int> streamMix() {
    final mix = <String, int>{};
    for (final e in instance.collection.entries) {
      final k = e.category.name;
      mix[k] = (mix[k] ?? 0) + 1;
    }
    return mix;
  }
}

Future<void> bootShared() async {
  final app = App.instance;
  if (app.booted) return;
  await app.township.load();
  await app.collection.load();
  await app.board.load();
  await app.catDex.load();
  await app.pipeline.load();
  await app.refs.loadPersisted();
  try {
    app.coreVersion = await TownshipCore.version();
    debugPrint('TWP:core ${app.coreVersion}');
  } catch (e) {
    debugPrint('TWP:ERROR core bridge: $e');
  }
  void bindStats() {
    final done = app.collection.entries.where((e) => e.status == 'done').length;
    app.stats.refresh(app.collection.points, app.collection.pending, done);
  }
  app.collection.addListener(bindStats);
  bindStats();
  app.aiReady = app.pipeline.ready;
  app.booted = true;
}

class Root extends StatefulWidget {
  const Root({super.key});

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  int _tab = 0;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _boot();
    // MainActivity delivers later `am start` imports on this channel.
    const MethodChannel('township/debug').setMethodCallHandler((call) async {
      if (call.method == 'importFile') {
        final path = call.arguments as String?;
        if (path != null && path.isNotEmpty) _acceptDebugImport(path);
      }
      return null;
    });
  }

  static void _acceptDebugImport(String path) {
    final handler = scanStateHandler;
    if (handler != null) {
      debugPrint('TWP:debug-import $path -> scan state');
      handler(path);
    } else {
      debugPrint('TWP:debug-import $path parked');
      App.pendingDebugImport = path;
      final ctx = _rootContext;
      if (ctx != null) {
        Navigator.of(ctx).pushNamed('/scan');
      }
    }
  }

  static BuildContext? _rootContext;

  Future<void> _boot() async {
    _rootContext = context;
    await bootShared();
    if (!mounted) return;
    setState(() => _ready = true);
    // adb debug-import hook: MainActivity stores a path, we consume it now.
    // No ScanScreen state may exist yet (Home is the first tab), so it waits
    // in App.pendingDebugImport until the scan tab registers a handler.
    try {
      final importPath = await TownshipCore.consumeDebugImport();
      if (importPath != null && importPath.isNotEmpty) {
        debugPrint('TWP:debug-import $importPath (parked until scan tab)');
        App.pendingDebugImport = importPath;
        if (mounted) Navigator.of(context).pushNamed('/scan');
      }
    } catch (e) {
      debugPrint('TWP:ERROR debug import: $e');
    }
    if (App.instance.township.onboardingDone) {
      if (!mounted) return;
      await TourOverlay.maybeShow(context, App.instance.township);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const SplashScreen();
    }
    final t = App.instance.township;
    if (!t.onboardingDone) {
      return OnboardingScreen(
        store: t,
        onDone: () {
          // First-run tour fires exactly once: onboarding completes, we swap
          // in the home shell, then — on the next frame — maybeShow runs.
          // maybeShow itself no-ops when tourDone, so returning users who
          // replay onboarding never see it twice.
          setState(() {});
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            TourOverlay.maybeShow(context, App.instance.township);
          });
        },
      );
    }

    final pages = <Widget>[
      HomeScreen(store: t, stats: App.instance.stats),
      ScanScreen(pipeline: App.instance.pipeline, store: App.instance.collection),
      CollectionScreen(store: App.instance.collection),
      HubScreen(store: t),
      MapScreen(store: t),
    ];

    return Scaffold(
      appBar: _appBar(),
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.camera_alt_outlined), selectedIcon: Icon(Icons.camera_alt), label: 'Scan'),
          NavigationDestination(icon: Icon(Icons.recycling_outlined), selectedIcon: Icon(Icons.recycling), label: 'Collection'),
          NavigationDestination(icon: Icon(Icons.volunteer_activism_outlined), selectedIcon: Icon(Icons.volunteer_activism), label: 'Hub'),
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Map'),
        ],
      ),
    );
  }

  PreferredSizeWidget _appBar() {
    // Home carries the branded title; the other tabs keep their section names.
    const titles = [
      'Township of Tomorrow',
      'Scan',
      'My collection',
      'Circular Hub',
      'Precinct map',
    ];
    return AppBar(
      title: Text(titles[_tab]),
      actions: [
        if (_tab == 0)
          IconButton(
            tooltip: 'Teach the scanner',
            icon: const Icon(Icons.school),
            onPressed: () => Navigator.pushNamed(context, '/teach'),
          ),
        if (App.instance.aiReady && _tab == 0)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Icon(Icons.bolt, color: context.tBrand, size: 18),
          ),
        if (App.instance.township.isStaff && _tab == 0)
          IconButton(
            tooltip: 'Command center',
            icon: const Icon(Icons.insights),
            onPressed: () => Navigator.pushNamed(context, '/command'),
          ),
        IconButton(
          tooltip: 'Profile & settings',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: () => Navigator.pushNamed(context, '/profile'),
          icon: Semantics(
            button: true,
            label: 'Profile & settings',
            child: CircleAvatar(
              radius: 16, // 32dp avatar inside a 48dp tap target
              backgroundColor: context.tTintGreen,
              child: Text(
                _residentInitial,
                style: TextStyle(
                  color: context.tBrand,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Resident initial shown in the app-bar avatar (fallback 'R' for
  /// residents who skipped the household name).
  String get _residentInitial {
    final name = App.instance.township.householdName?.trim() ?? '';
    return name.isEmpty ? 'R' : name[0].toUpperCase();
  }
}

// ── public staff gate for /operator (staff tier) and /command (council tier) ──

/// Wraps the staff-only routes. Non-staff residents get a plain explanation
/// plus a shortcut to Profile (where Staff mode lives); the guard listens to
/// the township store, so flipping Staff mode unlocks the route immediately
/// — council tier is the same [TownshipStore.isStaff] flag, no second role.
class StaffGuard extends StatelessWidget {
  final Widget child;

  /// Store override for tests; defaults to the app singleton.
  final TownshipStore? store;

  const StaffGuard({super.key, required this.child, this.store});

  @override
  Widget build(BuildContext context) {
    final s = store ?? App.instance.township;
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        if (s.isStaff) return child;
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline, size: 56, color: context.tMuted),
                    const SizedBox(height: 16),
                    Text(
                      'Staff access only',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: context.tInk,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'This area is for township staff. Turn on Staff mode in '
                      'Profile to continue.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.tMuted,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => Navigator.pushNamed(context, '/profile'),
                      child: const Text('Open profile'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── thin route wrappers that guarantee shared boot on deep links ────────────

Widget _withBoot(Widget child) => FutureBuilder(
      future: bootShared(),
      builder: (context, snap) => snap.connectionState == ConnectionState.done
          ? child
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    );

class _ScanRoute extends StatelessWidget {
  const _ScanRoute();

  @override
  Widget build(BuildContext context) => _withBoot(
        Scaffold(
          appBar: AppBar(title: const Text('Scan')),
          body: ScanScreen(
              pipeline: App.instance.pipeline, store: App.instance.collection),
        ),
      );
}

class _CollectionRoute extends StatelessWidget {
  const _CollectionRoute();

  @override
  Widget build(BuildContext context) => _withBoot(
        Scaffold(
          appBar: AppBar(title: const Text('My collection')),
          body: CollectionScreen(store: App.instance.collection),
        ),
      );
}

class _HubRoute extends StatelessWidget {
  const _HubRoute();

  @override
  Widget build(BuildContext context) => _withBoot(
        Scaffold(
          appBar: AppBar(title: const Text('Circular Hub')),
          body: HubScreen(store: App.instance.township),
        ),
      );
}

class _MapRoute extends StatelessWidget {
  const _MapRoute();

  @override
  Widget build(BuildContext context) => _withBoot(
        Scaffold(
          appBar: AppBar(title: const Text('Precinct map')),
          body: MapScreen(store: App.instance.township),
        ),
      );
}

class _ProfileRoute extends StatelessWidget {
  const _ProfileRoute();

  @override
  Widget build(BuildContext context) => _withBoot(
        Scaffold(
          appBar: AppBar(title: const Text('Profile & settings')),
          body: ProfileScreen(store: App.instance.township),
        ),
      );
}

class _OperatorRoute extends StatelessWidget {
  const _OperatorRoute();

  @override
  Widget build(BuildContext context) => _withBoot(
        StaffGuard(
          child: Scaffold(
            appBar: AppBar(title: const Text('Operator tier')),
            body: OperatorDashboard(store: App.instance.township),
          ),
        ),
      );
}

class _CommandRoute extends StatelessWidget {
  const _CommandRoute();

  @override
  Widget build(BuildContext context) => _withBoot(
        StaffGuard(
          child: Scaffold(
            appBar: AppBar(title: const Text('Council tier')),
            body: CommandCenterScreen(store: App.instance.township,
                streamMix: App.streamMix()),
          ),
        ),
      );
}

// ReportScreen and TeachScannerScreen own their Scaffold + AppBar — the
// routes below only guarantee shared boot and pass route arguments through.
class _ReportRoute extends StatelessWidget {
  const _ReportRoute();

  @override
  Widget build(BuildContext context) {
    final arg = ModalRoute.of(context)?.settings.arguments;
    return _withBoot(
      ReportScreen(
        store: App.instance.township,
        initialCategory: arg is String ? arg : null,
      ),
    );
  }
}

class _TeachRoute extends StatelessWidget {
  const _TeachRoute();

  @override
  Widget build(BuildContext context) => _withBoot(
        TeachScannerScreen(
            store: App.instance.township, refs: App.instance.refs),
      );
}

class _BoardRoute extends StatelessWidget {
  const _BoardRoute();

  @override
  Widget build(BuildContext context) => _withBoot(
        Scaffold(
          appBar: AppBar(title: const Text('Community Board')),
          body: CommunityBoardScreen(store: App.instance.board),
        ),
      );
}

class _CatDexRoute extends StatelessWidget {
  const _CatDexRoute();

  @override
  Widget build(BuildContext context) => _withBoot(
        Scaffold(
          appBar: AppBar(title: const Text('Cat Dex')),
          body: CatDexScreen(store: App.instance.catDex),
        ),
      );
}
