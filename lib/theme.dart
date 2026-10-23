/// Frozen design tokens + theme factory for Township of Tomorrow.
///
/// Every colour / radius here is a frozen product token (board 12). Screens
/// should pull values from these constants instead of inventing new ones.
///
/// Two themes are built from the same seed green: [buildTownshipTheme] takes a
/// [Brightness] and returns either the light or the dark Material 3 theme. The
/// light theme keeps the original board-12 values bit-for-bit (they are frozen
/// product tokens); the dark theme is `ColorScheme.fromSeed(brightness: dark)`
/// with manual tweaks that pin the exact brand colours the design needs
/// (seed green lifted for dark surfaces, near-black canvas, tinted dark
/// containers).
///
/// Screens must not hard-code `Color(0xFF…)` for surfaces or copy — use the
/// [TownshipPalette] extension on `BuildContext` (`context.tInk`,
/// `context.tCard`, …) so every screen follows the active theme. Colours that
/// are *canvas-correct* rather than theme-dependent (live-camera overlays,
/// saturated map-pin / category data colours, the amber warning chip and the
/// ink that pairs with it) stay frozen on purpose — see the token docs.
library;

import 'package:flutter/material.dart';

// ── colour tokens ──────────────────────────────────────────────────────────

/// Brand seed — primary green.
const Color kSeed = Color(0xFF2E7D32);

/// Deeper green for success copy on tints.
const Color kSuccessDark = Color(0xFF388E3C);

/// Warn amber. Always pair with [kOnAmber] copy: ink on amber is ~8.3:1,
/// comfortably clearing the 4.5:1 contrast floor.
const Color kWarnAmber = Color(0xFFF9A825);

/// Error / destructive.
const Color kError = Color(0xFFB71C1C);

/// Soft green tint (cards, callouts).
const Color kTintGreen = Color(0xFFE8F5E9);

/// Soft blue tint (info cards).
const Color kTintBlue = Color(0xFFE3F2FD);

/// Neutral 600 — secondary copy and icons on light surfaces.
const Color kNeutral600 = Color(0xFF616161);

/// Divider hairlines.
const Color kDivider = Color(0xFFE0E0E0);

/// App canvas background (light).
const Color kCanvas = Color(0xFFFAFAFA);

/// Primary text ink (light).
const Color kInk = Color(0xFF212121);

/// Text/icon colour for amber surfaces (see [kWarnAmber]).
const Color kOnAmber = kInk;

// ── dark-theme counterparts ────────────────────────────────────────────────
//
// One value per light token above; the [TownshipPalette] extension picks the
// side from `Theme.of(context).brightness`, so screens never branch on theme.

/// Brand green lifted for dark surfaces — #2E7D32 only clears ~2.6:1 on a
/// near-black canvas, so icons and accents use this 4.8:1 green instead.
const Color kSeedOnDark = Color(0xFF81C784);

/// App canvas background (dark).
const Color kCanvasDark = Color(0xFF121212);

/// Card / sheet surface (dark) — sits just above the canvas.
const Color kSurfaceDark = Color(0xFF1E1E1E);

/// Raised surface (dark) — dialogs, menus, the navigation bar.
const Color kSurfaceRaisedDark = Color(0xFF2C2C2C);

/// Primary text ink (dark).
const Color kInkDark = Color(0xFFF1F1F1);

/// Secondary copy / icons on dark surfaces (≈ neutral 300).
const Color kNeutral300 = Color(0xFFB3B3B3);

/// Low-emphasis copy on dark surfaces (≈ neutral 400).
const Color kNeutral400 = Color(0xFF9E9E9E);

/// Decorative placeholder glyphs on dark surfaces (≈ neutral 500).
const Color kNeutral500 = Color(0xFF7A7A7A);

/// Divider hairlines (dark).
const Color kDividerDark = Color(0xFF2E2E2E);

/// Soft green tint (dark counterpart of [kTintGreen]).
const Color kTintGreenDark = Color(0xFF17351A);

/// Soft blue tint (dark counterpart of [kTintBlue]).
const Color kTintBlueDark = Color(0xFF14324B);

/// Cream callout wash (dark counterpart of [kAmberWashLight]).
const Color kAmberWashDark = Color(0xFF33290F);

/// Warmer cream callout wash (dark counterpart of [kAmberWashWarmLight]).
const Color kAmberWashWarmDark = Color(0xFF3A2A12);

/// Copy that sits on an amber wash in dark mode.
const Color kAmberInkDark = Color(0xFFFFF1D0);

/// Secondary copy that sits on an amber wash in dark mode.
const Color kAmberMutedDark = Color(0xFFE3C98A);

/// Amber accent (icons) that sits on an amber wash in dark mode.
const Color kAmberAccentDark = Color(0xFFF0C75E);

/// Error / destructive on dark surfaces — M3's light red keeps 4.5:1+ where
/// the frozen #B71C1C would sink into the canvas.
const Color kErrorDark = Color(0xFFF2B8B5);

/// Cream callout wash (light — frozen product value).
const Color kAmberWashLight = Color(0xFFFFF8E1);

/// Warmer cream callout wash (light — frozen product value).
const Color kAmberWashWarmLight = Color(0xFFFFF3E0);

// ── shape tokens ───────────────────────────────────────────────────────────

/// Card / sheet corner radius.
const double kCardRadius = 12;

/// Chip corner radius.
const double kChipRadius = 10;

/// Pill / badge radius.
const double kPillRadius = 20;

/// Toggle (switch / segmented) corner radius.
const double kToggleRadius = 10;

// ── a11y tokens ────────────────────────────────────────────────────────────

/// Minimum hit target for filled / outlined / text buttons.
const double kMinButtonSize = 44;

// ── appearance setting ─────────────────────────────────────────────────────

/// Stored value for "follow the phone" — the persisted default.
const String kThemeModeSystem = 'system';

/// Maps the persisted setting (`system` | `light` | `dark`) onto [ThemeMode].
/// Unknown values fall back to [ThemeMode.system] so a corrupt settings file
/// can never lock the app into a theme nobody chose.
ThemeMode themeModeFromSetting(String raw) => switch (raw) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

/// Reverse mapping for persistence.
String themeSettingFromMode(ThemeMode mode) => switch (mode) {
  ThemeMode.light => 'light',
  ThemeMode.dark => 'dark',
  ThemeMode.system => kThemeModeSystem,
};

// ── theme factory ──────────────────────────────────────────────────────────

/// Builds the app theme from the frozen tokens. Material 3 with a green seed;
/// cards are flat (elevation 0), buttons guarantee a >=44dp target on top of
/// [MaterialTapTargetSize.padded], and default / focus / pressed / disabled /
/// error states stay stock M3 — only the hit target is overridden.
///
/// [brightness] picks the side: light (default) keeps every board-12 value
/// exactly; dark re-seeds from the same green with `brightness: dark` and then
/// pins the manual tweaks the design needs (lifted green, dark canvas,
/// dark containers, readable error red).
ThemeData buildTownshipTheme({Brightness brightness = Brightness.light}) {
  final isDark = brightness == Brightness.dark;
  final scheme = isDark
      ? _darkScheme()
      : ColorScheme.fromSeed(seedColor: kSeed, brightness: Brightness.light)
            .copyWith(
              // Exact brand green — fromSeed lands within a hair of it, the
              // frozen token pins it bit-for-bit.
              primary: kSeed,
              onPrimary: Colors.white,
              error: kError,
              onError: Colors.white,
              onSurface: kInk,
              onSurfaceVariant: kNeutral600,
              outlineVariant: kDivider,
              surfaceContainerLow: Colors.white,
            );
  const hitTarget = Size(kMinButtonSize, kMinButtonSize);
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
  return base.copyWith(
    scaffoldBackgroundColor: isDark ? kCanvasDark : kCanvas,
    dividerColor: isDark ? kDividerDark : kDivider,
    cardTheme: base.cardTheme.copyWith(
      elevation: 0,
      color: isDark ? kSurfaceDark : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardRadius),
        side: BorderSide(color: isDark ? kDividerDark : kDivider),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kChipRadius),
      ),
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: isDark ? kSurfaceDark : kCanvas,
      foregroundColor: isDark ? kInkDark : kInk,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      backgroundColor: isDark ? kSurfaceDark : Colors.white,
      indicatorColor: isDark
          ? kSeedOnDark.withValues(alpha: 0.24)
          : kTintGreen,
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: isDark ? kSurfaceRaisedDark : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardRadius),
      ),
    ),
    listTileTheme: base.listTileTheme.copyWith(
      // ListTile's own M3 defaults already take icon/title/subtitle colours
      // from the scheme — pinning the two overrides that screens inherit.
      iconColor: isDark ? kNeutral300 : kNeutral600,
      textColor: isDark ? kInkDark : kInk,
    ),
    snackBarTheme: base.snackBarTheme.copyWith(
      backgroundColor: isDark ? kSurfaceRaisedDark : kInk,
      contentTextStyle: base.textTheme.bodyMedium?.copyWith(
        color: isDark ? kInkDark : Colors.white,
      ),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: isDark ? kInkDark : kInk,
      displayColor: isDark ? kInkDark : kInk,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: hitTarget),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: hitTarget),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: hitTarget),
    ),
  );
}

/// `ColorScheme.fromSeed(brightness: dark)` plus the manual tweaks the dark
/// design needs: the seed green lifted to a readable tone, a near-black
/// canvas / card stack, and the light red error that survives on dark.
ColorScheme _darkScheme() =>
    ColorScheme.fromSeed(seedColor: kSeed, brightness: Brightness.dark)
        .copyWith(
          primary: kSeedOnDark,
          onPrimary: const Color(0xFF0B2810),
          primaryContainer: const Color(0xFF2E7D32),
          onPrimaryContainer: Colors.white,
          error: kErrorDark,
          onError: const Color(0xFF601410),
          surface: kCanvasDark,
          onSurface: kInkDark,
          onSurfaceVariant: kNeutral300,
          outline: kNeutral400,
          outlineVariant: kDividerDark,
          surfaceContainerLow: kSurfaceDark,
          surfaceContainer: kSurfaceDark,
          surfaceContainerHigh: kSurfaceRaisedDark,
          surfaceContainerHighest: kSurfaceRaisedDark,
          surfaceContainerLowest: kCanvasDark,
        );

// ── palette on context ─────────────────────────────────────────────────────

/// Semantic, theme-aware lookups for the frozen tokens.
///
/// Screens use these instead of raw `Color(0xFF…)` literals so every surface
/// and every line of copy follows the active [ThemeMode]. Each getter returns
/// exactly the frozen light value when the app is light — the dark side only
/// appears under the dark theme.
extension TownshipPalette on BuildContext {
  /// Active [ThemeData].
  ThemeData get tTheme => Theme.of(this);

  /// Active [ColorScheme].
  ColorScheme get tScheme => Theme.of(this).colorScheme;

  /// True when the dark theme is active.
  bool get tIsDark => Theme.of(this).brightness == Brightness.dark;

  /// Active [TextTheme].
  TextTheme get tText => tTheme.textTheme;

  /// Primary copy — the frozen ink on light, its dark counterpart on dark.
  Color get tInk => tIsDark ? kInkDark : kInk;

  /// Secondary copy / muted icons (was `kNeutral600` / `Colors.black54`).
  Color get tMuted => tIsDark ? kNeutral300 : kNeutral600;

  /// Low-emphasis copy (was `Colors.black45` / `Colors.black38`).
  Color get tFaint => tIsDark ? kNeutral400 : const Color(0xFF8F8F8F);

  /// Decorative placeholder glyphs — empty-state icons, pending step dots
  /// (was `Colors.black26` / `Colors.black12`).
  Color get tGhost => tIsDark ? kNeutral500 : const Color(0xFFBDBDBD);

  /// Card / sheet surface.
  Color get tCard => tIsDark ? kSurfaceDark : Colors.white;

  /// Raised surface (dialogs, bottom sheets).
  Color get tSurfaceRaised => tIsDark ? kSurfaceRaisedDark : Colors.white;

  /// Canvas background.
  Color get tCanvas => tTheme.scaffoldBackgroundColor;

  /// Hairline dividers and card borders.
  Color get tHairline => tIsDark ? kDividerDark : kDivider;

  /// Brand green accent on a themed surface (icons, indicators, badges).
  Color get tBrand => tIsDark ? kSeedOnDark : kSeed;

  /// Error accent on a themed surface.
  Color get tError => tIsDark ? kErrorDark : kError;

  /// Soft green tint (status cards, callouts).
  Color get tTintGreen => tIsDark ? kTintGreenDark : kTintGreen;

  /// Soft blue tint (info cards).
  Color get tTintBlue => tIsDark ? kTintBlueDark : kTintBlue;

  /// Cream callout wash — pair copy with [tAmberInk] / [tAmberMuted].
  Color get tAmberWash => tIsDark ? kAmberWashDark : kAmberWashLight;

  /// Warmer cream callout wash — pair copy with [tAmberInk] / [tAmberMuted].
  Color get tAmberWashWarm => tIsDark
      ? kAmberWashWarmDark
      : kAmberWashWarmLight;

  /// Primary copy on [tAmberWash] / [tAmberWashWarm].
  Color get tAmberInk => tIsDark ? kAmberInkDark : kInk;

  /// Secondary copy on [tAmberWash] / [tAmberWashWarm].
  Color get tAmberMuted => tIsDark ? kAmberMutedDark : const Color(0xFF6D4C00);

  /// Amber accent (icons) on [tAmberWash] / [tAmberWashWarm].
  Color get tAmberAccent => tIsDark ? kAmberAccentDark : const Color(0xFF8D6E00);

  /// Info accent (blue) on a tint-blue panel — the frozen #1565C0 in light,
  /// lifted for the dark tint.
  Color get tInfo => tIsDark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0);

  /// Amber-family icon accent on an amber wash (cat card, paw glyph).
  Color get tAmberIcon =>
      tIsDark ? const Color(0xFFFFB74D) : const Color(0xFFEF6C00);

  /// Progress track drawn on a tint surface: white in light, a lifted green
  /// wash in dark so the empty track does not glare.
  Color get tTrack =>
      tIsDark ? Colors.white.withValues(alpha: 0.18) : Colors.white;

  /// Primary copy on a tint chip (tint-blue / tint-green): the frozen
  /// black87 on light, the dark ink on dark — the light value is what the
  /// contrast tests pin, so it stays bit-for-bit.
  Color get tTintInk => tIsDark ? kInkDark : Colors.black87;

  /// Success accent (stat numbers, "resolved" markers).
  Color get tSuccess => tIsDark ? kSeedOnDark : kSuccessDark;

  /// Flat track / placeholder fill that follows the canvas (was
  /// `Colors.black12` on light surfaces).
  Color get tScrim => tIsDark
      ? Colors.white.withValues(alpha: 0.10)
      : Colors.black.withValues(alpha: 0.12);
}
