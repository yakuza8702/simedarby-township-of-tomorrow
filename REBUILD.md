# Rebuild (Flutter + Go) — go core 0.2.1, full legacy surface

```bash
export PATH=/workspace/toolchain/flutter/bin:$PATH
export ANDROID_HOME=/workspace/simedarby-hackathon-student/android-sdk
export ANDROID_SDK_ROOT=$ANDROID_HOME
unset ANDROID_PREFS_ROOT            # AGP hard-fails when both env vars are set

# x86_64 emulator test build
flutter build apk --debug --target-platform android-x64 \
  -Ptownship.abiFilters=x86_64 --android-skip-build-dependency-validation

# FINAL Android-compatible build (arm64-v8a + armeabi-v7a only)
flutter build apk --release --target-platform android-arm,android-arm64 \
  --android-skip-build-dependency-validation
```

- Go core: `cd go/townshipcore && gomobile bind -target=android -androidapi 24 \
  -o ../../android/app/libs/townshipcore.aar .`
- `--android-skip-build-dependency-validation` is needed because this
  timeline's AGP embeds KGP 2.2.10 while Flutter 3.47.7 checks >= 2.2.20
  (the classpath actually runs the catalog's 2.2.21).
- The jni plugin (tflite) leaks x86_64 `.so`s into release APKs regardless of
  abiFilters; strip them with a zip repack and re-sign with apksigner.

## Ported surfaces (go core 0.2.1, full legacy parity)
- Onboarding (household + precinct + PDPA consent) and the 4-step first tour
- Home (status card, quick actions, impact ledger)
- Scan (camera + photo import, EfficientDet + ML Kit (always-on) + kNN bonus)
- Collection: confirm → add → recycle/remove/dispose with proof-photo verify
- Circular Hub (list/hold the item), Precinct map (bin grid + legend)
- Hazard reports (photo + severity + queued), Operator tier (Profile → staff
  mode, route /operator), Command center (route /command)
- Teach the scanner: photo → name → stream → on-device kNN reference
- OCR "read printed text" via ML Kit text recognition

## Final arm64 build (0.3.0-b)

The shipping artifact is produced by **one script** — `tool/build_final_arm64.sh`
(set -euo pipefail, non-interactive, single-threaded; gradle.properties caps
the daemon at `-Xmx2g` / `org.gradle.workers.max=2`, so run one gradle/Flutter
invocation at time and no parallel jobs):

```bash
cd "Township of Tomorrow Flutter"
./tool/build_final_arm64.sh
```

> **Container environment notes** (all handled *inside* the script — no
> project source file is modified): `/opt/android-sdk` sits on a read-only
> root overlay, so AGP/Flutter cannot install anything into it. The script
> therefore provisions, idempotently:
> (a) a **writable SDK view** (`/workspace/android-sdk-view`: symlink farm of
> the real SDK + real writable `ndk/` and `.sdk/`) exported as
> `ANDROID_HOME`/`ANDROID_SDK_ROOT` — the flutter tool prefers the env over
> `local.properties`, sees NDK **28.2.13676358** (= `flutter.ndkVersion`) in
> `flutter.installedNdkVersions`, and its Gradle plugin's NDK provisioning
> short-circuits instead of crashing on the read-only sdkmanager lock;
> flutter's own `updateLocalProperties()` then rewrites `sdk.dir` to the
> view, making it the (writable) Gradle SDK root too — the script detects
> this steady state and rebuilds the view from the real SDK;
> (b) a `GRADLE_USER_HOME/init.d/wo10-ndkpath.gradle` that pins every AGP
> project to the packages that exist: `android.ndkPath` (NDK above),
> `buildToolsVersion 36.1.0`, `compileSdk 36` (plugins that pin 35 would
> demand `build-tools;35.0.0` / `platforms;android-35`, absent here);
> (c) CMake **3.22.1** (AGP's `CMakeVersion.DEFAULT`) unpacked under
> `/workspace/toolchain/cmake-sdk` with `bin` on `PATH` (`CmakeLocator`
> accepts environment PATH candidates — there is no `sdk/cmake` package);
> (d) stale gradle-daemon shutdown before building (a long-lived daemon can
> hold dead HTTP connections → `Network is unreachable` on dependency fetch;
> flutter's gradle retry then also recovers transient Maven flakes).
> One earlier toolchain fix is likewise outside the project tree:
> `flutter_tools/gradle` has AGP 8.11.1 as an `implementation` (not
> `compileOnly`) dependency so the project's root build script can resolve
> `com.android.build.gradle.BaseExtension` — the state documented by
> `android/gradle/libs.versions.toml`. Measured on this container: full
> pipeline ≈ 5.5 min warm (`flutter build apk` ≈ 327 s of it; first-ever run
> additionally downloads Gradle 9.3.1 + AGP/KGP deps).

What the script does, in order (the exact commands, expanded):

```bash
# 1. root + env resolved from android/local.properties (sdk.dir, flutter.sdk)
export PATH="/workspace/toolchain/flutter/bin:$PATH"
export ANDROID_HOME=/opt/android-sdk
export ANDROID_SDK_ROOT=/opt/android-sdk

# 2. build: release, ONE abi, project override caps ndk.abiFilters
#    (no `--` separator: Flutter 3.47.7 treats post-`--` args as extra
#     build *targets*; -P… gradle properties are passed directly)
flutter build apk --release --target-platform android-arm64 \
  --android-skip-build-dependency-validation \
  -Ptownship.abiFilters=arm64-v8a \
  -Pandroid.builder.sdkDownload=false

# 3. repack (python3 zipfile pass): DELETE lib/x86_64/, lib/x86/,
#    lib/armeabi-v7a/ entries; keep lib/arm64-v8a/, assets/, META-INF/ intact
python3 tool/repack-inline   # inlined in the script: ZipFile read → rewrite

# 4. re-page-align the native libs (build-tools 36.1.0)
/opt/android-sdk/build-tools/36.1.0/zipalign -p -f 4 \
  app-release-stripped.apk app-release-aligned.apk

# 5. keystore (only if android/app/debug.keystore is missing)
keytool -genkeypair -keystore android/app/debug.keystore -storepass android \
  -alias androiddebugkey -keypass android \
  -dname 'CN=Android Debug,O=Android,C=US' \
  -keyalg RSA -keysize 2048 -validity 10000 -noprompt

# 6. sign + verify (verify must exit 0)
/opt/android-sdk/build-tools/36.1.0/apksigner sign \
  --ks android/app/debug.keystore --ks-pass pass:android --key-pass pass:android \
  --ks-key-alias androiddebugkey --out app-release-signed.apk app-release-aligned.apk
/opt/android-sdk/build-tools/36.1.0/apksigner verify app-release-signed.apk

# 7. publish to the workspace root under the canonical name
cp app-release-signed.apk \
  ../Township-of-Tomorrow_v0.3.0-b-android-arm64.apk
```

**Why the strip/repack step exists:** the tflite/jni plugin leaks x86_64 (and
sometimes x86 / armeabi-v7a) `.so` files into `lib/` of release APKs *regardless
of* `ndk.abiFilters` — the plugin's own packaging copies prebuilt binaries
past the manifest merge. `--target-platform android-arm64` +
`-Ptownship.abiFilters=arm64-v8a` already keep Flutter's own outputs to a single
ABI, but the leaked foreign `.so`s survive, inflate the APK by tens of MB, and
make the artifact claim ABIs it was never tested on. The python3 zipfile pass
removes exactly those entries (`lib/x86_64/`, `lib/x86/`, `lib/armeabi-v7a/`),
copies everything else byte-for-byte (arm64 libs, assets, resources,
META-INF), after which `zipalign -p 4` restores page alignment of the stored
`.so`s and apksigner re-signs — an unsigned repack would fail install.

**Verification checklist** (the script gates on all of these; exit 1 on any
miss — also runnable by hand after the build):

```bash
APK=../Township-of-Tomorrow_v0.3.0-b-android-arm64.apk
unzip -l "$APK" | grep -E 'lib/(x86_64|x86|armeabi-v7a)/'   # expect NO output
/opt/android-sdk/build-tools/36.1.0/aapt2 dump badging "$APK" | grep native-code
                                                              # native-code: 'arm64-v8a'
/opt/android-sdk/build-tools/36.1.0/apksigner verify "$APK"   # exit 0
sha256sum "$APK"
```

- [ ] `bash -n tool/build_final_arm64.sh` passes
- [ ] `unzip -l` shows **zero** `lib/(x86_64|x86|armeabi-v7a)/` entries
- [ ] `aapt2 dump badging` reports `native-code: 'arm64-v8a'` (only)
- [ ] `apksigner verify` exits 0
- [ ] APK lands at the workspace root as
      `Township-of-Tomorrow_v0.3.0-b-android-arm64.apk`
- [ ] versionName `0.3.0-b` / versionCode 4 (from `gradle/libs.versions.toml`)

**Only arm64-v8a ships.** The x86_64 build (`-Ptownship.abiFilters=x86_64`)
exists solely for the headless emulator and must never be published; armeabi-v7a
is not shipped in 0.3.0-b — the release APK targets arm64 devices only, and the
badging gate above enforces that on every build.
