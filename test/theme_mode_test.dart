/// Theme system tests (dark/light mode): the two ThemeData factories from the
/// one seed green, the persisted appearance setting, the palette lookups the
/// screens use, and the Profile picker that flips the mode end-to-end
/// (MaterialApp reports a changed ColorScheme after the pick).
///
/// TownshipStore persists through path_provider; the platform channel is
/// mocked to a TempDir so no real app-documents dir is touched.
///
/// Run: `flutter test test/theme_mode_test.dart`
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:township_of_tomorrow/screens/profile_screen.dart';
import 'package:township_of_tomorrow/store/township_store.dart';
import 'package:township_of_tomorrow/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tmp;
  late TownshipStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('theme_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return tmp.path;
          }
          return null;
        });
    // Real file I/O: keep it out of the fake-async testWidgets zone (the same
    // pattern profile_screen_test uses — load in setUp, flush writes with
    // tester.runAsync).
    store = TownshipStore();
    await store.load();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('light theme keeps the frozen board-12 tokens bit-for-bit', () {
    final light = buildTownshipTheme();
    expect(light.brightness, Brightness.light);
    expect(light.colorScheme.primary, kSeed);
    expect(light.colorScheme.onPrimary, Colors.white);
    expect(light.colorScheme.error, kError);
    expect(light.colorScheme.onSurface, kInk);
    expect(light.colorScheme.onSurfaceVariant, kNeutral600);
    expect(light.scaffoldBackgroundColor, kCanvas);
    expect(light.dividerColor, kDivider);
    expect(light.cardTheme.color, Colors.white);
  });

  test('dark theme is fromSeed(dark) plus the manual brand tweaks', () {
    final dark = buildTownshipTheme(brightness: Brightness.dark);
    expect(dark.brightness, Brightness.dark);
    expect(dark.scaffoldBackgroundColor, kCanvasDark);
    expect(dark.dividerColor, kDividerDark);
    expect(dark.cardTheme.color, kSurfaceDark);
    expect(dark.colorScheme.primary, kSeedOnDark); // lifted seed green
    expect(dark.colorScheme.error, kErrorDark);
    expect(dark.colorScheme.onSurface, kInkDark);
    expect(dark.colorScheme.onSurfaceVariant, kNeutral300);
    // Same seed family, different tone: dark primary must not be the light one.
    expect(
      dark.colorScheme.primary,
      isNot(buildTownshipTheme().colorScheme.primary),
    );
    expect(dark.colorScheme.primaryContainer, kSeed);
  });

  test('appearance setting maps to ThemeMode and survives junk', () {
    expect(themeModeFromSetting(kThemeModeSystem), ThemeMode.system);
    expect(themeModeFromSetting('light'), ThemeMode.light);
    expect(themeModeFromSetting('dark'), ThemeMode.dark);
    // A corrupt settings file can never lock the app into a chosen theme.
    expect(themeModeFromSetting('neon'), ThemeMode.system);
    expect(themeSettingFromMode(ThemeMode.system), kThemeModeSystem);
    expect(themeSettingFromMode(ThemeMode.light), 'light');
    expect(themeSettingFromMode(ThemeMode.dark), 'dark');
  });

  test('palette lookups return the frozen light values by default', () {
    // Documented contract: every t* getter equals the old literal in light,
    // so the sweep changed nothing for light-mode residents.
    expect(kSeedOnDark, const Color(0xFF81C784));
    expect(kCanvasDark, const Color(0xFF121212));
    expect(kSurfaceDark, const Color(0xFF1E1E1E));
    expect(kInkDark, const Color(0xFFF1F1F1));
    expect(kNeutral300, const Color(0xFFB3B3B3));
    expect(kDividerDark, const Color(0xFF2E2E2E));
    expect(kTintGreenDark, const Color(0xFF17351A));
    expect(kTintBlueDark, const Color(0xFF14324B));
    expect(kErrorDark, const Color(0xFFF2B8B5));
    expect(kAmberWashLight, const Color(0xFFFFF8E1));
    expect(kAmberWashWarmLight, const Color(0xFFFFF3E0));
  });

  testWidgets('palette getters flip with the active theme', (tester) async {
    Color? ink;
    Color? card;
    Color? brand;
    Color? tint;
    Color? hairline;
    Brightness? brightness;

    Widget host(ThemeMode mode) => MaterialApp(
      theme: buildTownshipTheme(),
      darkTheme: buildTownshipTheme(brightness: Brightness.dark),
      themeMode: mode,
      home: Builder(
        builder: (context) {
          brightness = Theme.of(context).brightness;
          ink = context.tInk;
          card = context.tCard;
          brand = context.tBrand;
          tint = context.tTintGreen;
          hairline = context.tHairline;
          return const SizedBox();
        },
      ),
    );

    await tester.pumpWidget(host(ThemeMode.light));
    await tester.pumpAndSettle();
    expect(brightness, Brightness.light);
    expect(ink, kInk);
    expect(card, Colors.white);
    expect(brand, kSeed);
    expect(tint, kTintGreen);
    expect(hairline, kDivider);

    await tester.pumpWidget(host(ThemeMode.dark));
    await tester.pumpAndSettle();
    expect(brightness, Brightness.dark);
    expect(ink, kInkDark);
    expect(card, kSurfaceDark);
    expect(brand, kSeedOnDark);
    expect(tint, kTintGreenDark);
    expect(hairline, kDividerDark);
  });

  test('appearance choice persists in township_state.json', () async {
    expect(store.themeMode, kThemeModeSystem);

    store.setThemeMode('dark');
    // Fire-and-forget write (same pattern as the other store setters).
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final raw = await File('${tmp.path}/township_state.json').readAsString();
    final j = jsonDecode(raw) as Map<String, dynamic>;
    expect(j['themeMode'], 'dark');

    final reloaded = TownshipStore();
    await reloaded.load();
    expect(reloaded.themeMode, 'dark');
    expect(themeModeFromSetting(reloaded.themeMode), ThemeMode.dark);
  });

  testWidgets('Profile picker flips the mode and the ColorScheme follows', (
    tester,
  ) async {
    // The same wiring main.dart ships: one store listener drives MaterialApp.
    Widget host() => AnimatedBuilder(
      animation: store,
      builder: (context, _) => MaterialApp(
        theme: buildTownshipTheme(),
        darkTheme: buildTownshipTheme(brightness: Brightness.dark),
        themeMode: themeModeFromSetting(store.themeMode),
        home: Scaffold(body: ProfileScreen(store: store)),
      ),
    );

    await tester.pumpWidget(host());
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('System default'), findsOneWidget); // caption

    ThemeData themeNow() =>
        Theme.of(tester.element(find.text('Appearance')));
    expect(themeNow().brightness, Brightness.light);
    expect(themeNow().colorScheme.primary, kSeed);

    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();
    expect(find.text('Choose theme'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(store.themeMode, 'dark');
    expect(find.text('Dark'), findsOneWidget); // caption now reads Dark
    expect(find.text('Choose theme'), findsNothing);
    // The MaterialApp rebuilt → the whole screen renders on the dark scheme.
    expect(themeNow().brightness, Brightness.dark);
    expect(themeNow().colorScheme.primary, kSeedOnDark);
    expect(themeNow().scaffoldBackgroundColor, kCanvasDark);

    // Back to the phone's own setting.
    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('System default'));
    await tester.pumpAndSettle();
    expect(store.themeMode, kThemeModeSystem);
    expect(find.text('System default'), findsOneWidget);
  });
}
