#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# WO-10 FINAL build pipeline — arm64-only release APK (v0.3.0-b).
#
#   1. Resolve project root from this script's own location (tool/..).
#   2. Read sdk.dir + flutter.sdk from android/local.properties; export
#      PATH (flutter bin) + ANDROID_HOME/ANDROID_SDK_ROOT; verify flutter+java.
#   2b. Environment provisioning for this read-only-SDK container (no project
#      file modified): GRADLE_USER_HOME init script injects android.ndkPath
#      (pre-provisioned NDK 28.2.13676358 = flutter.ndkVersion) and CMake
#      3.22.1 (AGP default) is unpacked under /workspace/toolchain + put on
#      PATH (AGP CmakeLocator accepts environment PATH candidates); stale
#      gradle daemons are stopped before building.
#   3. flutter build apk --release --target-platform android-arm64 ...
#      with the project's -Ptownship.abiFilters=arm64-v8a override.
#   4. Repack with python3 zipfile: strip the tflite/jni x86 leak
#      (lib/x86_64/, lib/x86/, lib/armeabi-v7a/); keep lib/arm64-v8a/,
#      assets/, META-INF/ intact.
#   5. zipalign -p 4 (build-tools 36.1.0), apksigner sign + verify with the
#      debug keystore (generated on demand).
#   6. Gate: no lib/(x86_64|x86|armeabi-v7a)/ entries, badging says
#      native-code: 'arm64-v8a', apksigner verify exits 0.
#   7. Copy the verified APK to the workspace root under the canonical name.
#
# Non-interactive; single-threaded (gradle.properties caps jvm 2g / workers 2).
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── 1. project root from script location ────────────────────────────────────
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
LOCAL_PROPERTIES="${PROJECT_ROOT}/android/local.properties"
[ -f "${LOCAL_PROPERTIES}" ] || { echo "FATAL: missing ${LOCAL_PROPERTIES}"; exit 1; }

# ── 2. sdk.dir + flutter.sdk from local.properties ──────────────────────────
prop() { sed -n "s/^$1=//p" "${LOCAL_PROPERTIES}" | head -n1; }
SDK_DIR="$(prop 'sdk\.dir')"
FLUTTER_SDK="$(prop 'flutter\.sdk')"
[ -n "${SDK_DIR}" ]    || { echo "FATAL: sdk.dir not set in android/local.properties"; exit 1; }
[ -n "${FLUTTER_SDK}" ] || { echo "FATAL: flutter.sdk not set in android/local.properties"; exit 1; }
[ -d "${SDK_DIR}" ]    || { echo "FATAL: sdk.dir '${SDK_DIR}' is not a directory"; exit 1; }
[ -d "${FLUTTER_SDK}" ] || { echo "FATAL: flutter.sdk '${FLUTTER_SDK}' is not a directory"; exit 1; }

export PATH="${FLUTTER_SDK}/bin:${PATH}"

command -v flutter >/dev/null 2>&1 || { echo "FATAL: flutter not found on PATH (${FLUTTER_SDK}/bin)"; exit 1; }
command -v java    >/dev/null 2>&1 || { echo "FATAL: java not found on PATH"; exit 1; }

# ── 2b. environment provisioning (read-only /opt/android-sdk) ────────────────
# The container's root overlay is read-only, so nothing can be INSTALLED into
# ${SDK_DIR} and it ships no NDK/cmake packages. Env-only provisions (no
# project file is modified — local.properties keeps sdk.dir=/opt/android-sdk,
# which AGP honours over env):
#   (i)  A writable SDK VIEW (symlink farm) is exposed to the FLUTTER TOOL
#        via ANDROID_HOME (flutter's locateAndroidSdk prefers the env over
#        local.properties). Its ndk/ dir makes the pre-provisioned NDK
#        28.2.13676358 (= flutter.ndkVersion) visible in
#        flutter.installedNdkVersions, so the Flutter Gradle plugin's NDK
#        provisioning (which would exec `sdkmanager --install ndk;…` and
#        crash on the read-only SDK lock) short-circuits and never runs.
#   (ii) NDK for AGP: a GRADLE_USER_HOME init script sets android.ndkPath on
#        every AGP project (NdkLocator checks ndkPath before sdk/ndk/<v>).
#   (iii) CMake 3.22.1 (AGP's CMakeVersion.DEFAULT): unpacked under
#        /workspace/toolchain, bin on PATH (CmakeLocator accepts env PATH
#        candidates).
NDK_DIR="${WO10_NDK_DIR:-/workspace/simedarby-hackathon-student/_cleanup_preserved/android-sdk/ndk/28.2.13676358}"
[ -f "${NDK_DIR}/source.properties" ] || { echo "FATAL: NDK not found at ${NDK_DIR}"; exit 1; }

SDK_VIEW="${WO10_SDK_VIEW:-/workspace/android-sdk-view}"
# Flutter's updateLocalProperties() rewrites sdk.dir to whatever SDK the tool
# located (ANDROID_HOME → the view) BEFORE invoking gradle, so from the second
# run onward local.properties points INTO the view. Resolve the real (read-only)
# SDK base regardless: /opt/android-sdk when sdk.dir is the view, else sdk.dir.
REAL_SDK_BASE="${WO10_REAL_SDK:-}"
if [ -z "${REAL_SDK_BASE}" ]; then
  case "${SDK_DIR}" in
    "${SDK_VIEW}"|"${SDK_VIEW}"/*) REAL_SDK_BASE="/opt/android-sdk" ;;
    *)                               REAL_SDK_BASE="${SDK_DIR}" ;;
  esac
fi
[ -d "${REAL_SDK_BASE}/build-tools" ] || { echo "FATAL: real SDK base not found: ${REAL_SDK_BASE}"; exit 1; }
if [ "$(cd -- "${REAL_SDK_BASE}" && pwd -P)" = "$(cd -- "${SDK_VIEW}" 2>/dev/null && pwd -P)" ]; then
  echo "FATAL: real SDK base must not be the view itself"; exit 1
fi

# Rebuild the view: drop stale symlinks (a previous run may have self-linked
# entries when sdk.dir already pointed at the view), then link every real-SDK
# top-level entry except ndk/ and .sdk/, which stay real writable dirs.
mkdir -p "${SDK_VIEW}/ndk" "${SDK_VIEW}/.sdk"
find "${SDK_VIEW}" -maxdepth 1 -type l -delete
for entry in "${REAL_SDK_BASE}"/* "${REAL_SDK_BASE}"/.[!.]*; do
  [ -e "${entry}" ] || continue
  base="$(basename -- "${entry}")"
  [ "${base}" = "ndk" ] && continue   # real dir, populated below
  [ "${base}" = ".sdk" ] && continue  # real dir (would-be lock area)
  ln -sfn -- "${entry}" "${SDK_VIEW}/${base}"
done
ln -sfn -- "${NDK_DIR}" "${SDK_VIEW}/ndk/$(basename -- "${NDK_DIR}")"

export ANDROID_HOME="${SDK_VIEW}"
export ANDROID_SDK_ROOT="${SDK_VIEW}"

BUILD_TOOLS="${REAL_SDK_BASE}/build-tools/36.1.0"
ZIPALIGN="${BUILD_TOOLS}/zipalign"
AAPT2="${BUILD_TOOLS}/aapt2"
APKSIGNER="${BUILD_TOOLS}/apksigner"
for tool in "${ZIPALIGN}" "${AAPT2}" "${APKSIGNER}"; do
  [ -x "${tool}" ] || { echo "FATAL: missing executable ${tool}"; exit 1; }
done

GRADLE_USER_HOME="${GRADLE_USER_HOME:-${HOME}/.gradle}"
mkdir -p "${GRADLE_USER_HOME}/init.d"
cat > "${GRADLE_USER_HOME}/init.d/wo10-ndkpath.gradle" <<EOF
// WO-10 env fix: /opt/android-sdk is read-only, so AGP cannot auto-install
// missing SDK packages (NDK, build-tools 35.0.0, platforms;android-35 all
// requested by plugins that pin older revisions). No project file may be
// modified, so this init script pins EVERY AGP project to the packages that
// ARE present in the read-only SDK:
//   * android.ndkPath        -> pre-provisioned NDK (28.2.13676358)
//   * android.buildToolsVersion -> 36.1.0 (installed)
//   * android.compileSdk      -> 36 (platforms/android-36 installed)
// Applied in finalizeDsl (the DSL-freeze hook, before variant/task creation,
// and before the Flutter plugin's own finalizeDsl callbacks registered later)
// with an afterEvaluate re-assert as fallback.
def wo10Ndk = '${NDK_DIR}'
def wo10Pin = { ext ->
    try { ext.ndkPath = wo10Ndk } catch (Throwable ignored) {}
    try { if (ext.buildToolsVersion?.toString() != '36.1.0') ext.buildToolsVersion = '36.1.0' } catch (Throwable ignored) {}
    try { ext.compileSdk = 36 } catch (Throwable ignored) {}
}
def wo10Apply = { proj ->
    def hook = {
        proj.plugins.withId('com.android.application') {
            def ac = proj.extensions.findByName('androidComponents')
            if (ac != null) { try { ac.finalizeDsl { ext -> wo10Pin(ext) } } catch (Throwable ignored) {} }
        }
        proj.plugins.withId('com.android.library') {
            def ac = proj.extensions.findByName('androidComponents')
            if (ac != null) { try { ac.finalizeDsl { ext -> wo10Pin(ext) } } catch (Throwable ignored) {} }
        }
        proj.afterEvaluate {
            def ext = proj.extensions.findByName('android')
            if (ext != null) { wo10Pin(ext) }
        }
    }
    hook()
}
allprojects { p -> wo10Apply(p) }
EOF

CMAKE_ROOT="${WO10_CMAKE_ROOT:-/workspace/toolchain/cmake-sdk}"
if [ ! -x "${CMAKE_ROOT}/bin/cmake" ]; then
  echo "--- provisioning CMake 3.22.1 into ${CMAKE_ROOT} ---"
  mkdir -p "${CMAKE_ROOT}"
  CMAKE_ZIP="${CMAKE_ROOT}/cmake-3.22.1-linux.zip"
  if [ ! -s "${CMAKE_ZIP}" ]; then
    curl -fsSL --connect-timeout 30 -o "${CMAKE_ZIP}" \
      "https://dl.google.com/android/repository/cmake-3.22.1-linux.zip" \
      || { echo "FATAL: cannot download CMake package"; exit 1; }
  fi
  unzip -q -o "${CMAKE_ZIP}" -d "${CMAKE_ROOT}"
fi
export PATH="${CMAKE_ROOT}/bin:${PATH}"
command -v cmake >/dev/null 2>&1 || { echo "FATAL: cmake not found on PATH"; exit 1; }

# Drop any stale gradle daemon before the build (a long-lived daemon can hold
# dead pooled HTTP connections; "Network is unreachable" on dependency fetch).
( cd "${PROJECT_ROOT}/android" && ./gradlew --stop >/dev/null 2>&1 ) || true

echo "=== WO-10 FINAL arm64 build ==="
echo "project root : ${PROJECT_ROOT}"
echo "flutter      : $(flutter --version 2>/dev/null | head -n1)"
echo "java         : $(java -version 2>&1 | head -n1)"
echo "sdk (real)   : ${REAL_SDK_BASE}"
echo "sdk (build)  : ${ANDROID_HOME}  (view; ndk/ writable-visible)"
echo "ndk (init.d) : ${NDK_DIR}"
echo "cmake (PATH) : $(cmake --version 2>/dev/null | head -n1)"

# ── versionName (informational; filename must stay canonical) ───────────────
VERSION_NAME="$(sed -n 's/^township *= *"\(.*\)".*/\1/p' "${PROJECT_ROOT}/android/gradle/libs.versions.toml" | head -n1)"
VERSION_NAME="${VERSION_NAME:-0.3.0-b}"

# ── 3. flutter build (release, arm64 only) ──────────────────────────────────
cd "${PROJECT_ROOT}"
T_BUILD_START=$(date +%s)
echo "--- flutter build apk --release --target-platform android-arm64 ---"
# NOTE: this Flutter CLI treats post-`--` args as extra build *targets*
# ("Target file \"-P…\" not found"), so the project's abiFilters gradle
# property is passed directly, matching the proven REBUILD.md invocation.
# -Pandroid.builder.sdkDownload=false: the SDK root is read-only; every
# required package (platform android-36, build-tools 36.1.0, NDK via
# android.ndkPath, cmake via PATH) is pre-provisioned, so AGP's auto-installer
# must not run — it crashes on /opt/android-sdk/.sdk/lock (EROFS).
flutter build apk --release \
  --target-platform android-arm64 \
  --android-skip-build-dependency-validation \
  -Ptownship.abiFilters=arm64-v8a \
  -Pandroid.builder.sdkDownload=false
T_BUILD_END=$(date +%s)
echo "flutter build finished in $((T_BUILD_END - T_BUILD_START))s"

BUILT_APK="${PROJECT_ROOT}/build/app/outputs/flutter-apk/app-release.apk"
[ -f "${BUILT_APK}" ] || { echo "FATAL: build output missing: ${BUILT_APK}"; exit 1; }

# ── 4. repack: strip x86 / x86_64 / armeabi-v7a (tflite/jni leak) ───────────
WORK_DIR="$(mktemp -d "${PROJECT_ROOT}/build/wo10-repack.XXXXXX")"
trap 'rm -rf "${WORK_DIR}"' EXIT
STRIPPED_APK="${WORK_DIR}/app-release-stripped.apk"

echo "--- repack: remove lib/x86_64/ lib/x86/ lib/armeabi-v7a/ ---"
python3 - "${BUILT_APK}" "${STRIPPED_APK}" <<'PYEOF'
import sys, zipfile

src, dst = sys.argv[1], sys.argv[2]
BAD = ("lib/x86_64/", "lib/x86/", "lib/armeabi-v7a/")
removed, kept = [], 0

with zipfile.ZipFile(src) as zin, \
     zipfile.ZipFile(dst, "w") as zout:
    for info in zin.infolist():
        if info.filename.startswith(BAD):
            removed.append(info.filename)
            continue
        # copy entry metadata (incl. STORED libs) verbatim; keep data intact.
        ni = zipfile.ZipInfo(info.filename, date_time=info.date_time)
        ni.compress_type = info.compress_type
        ni.external_attr = info.external_attr
        ni.create_system = info.create_system
        ni.create_version = info.create_version
        ni.extract_version = info.extract_version
        zout.writestr(ni, zin.read(info.filename))
        kept += 1

print(f"repack: kept {kept} entries, removed {len(removed)} foreign-ABI entries")
for name in removed:
    print(f"  - {name}")
if kept == 0:
    sys.exit("FATAL: repack produced an empty APK")
PYEOF
[ -s "${STRIPPED_APK}" ] || { echo "FATAL: repack output missing/empty"; exit 1; }

# ── 5a. zipalign -p 4 (page-align native libs) ──────────────────────────────
ALIGNED_APK="${WORK_DIR}/app-release-aligned.apk"
echo "--- zipalign -p 4 ---"
"${ZIPALIGN}" -p -f -v 4 "${STRIPPED_APK}" "${ALIGNED_APK}" | tail -n2
[ -s "${ALIGNED_APK}" ] || { echo "FATAL: zipalign output missing/empty"; exit 1; }

# ── 5b. debug keystore on demand ────────────────────────────────────────────
KEYSTORE="${PROJECT_ROOT}/android/app/debug.keystore"
if [ ! -f "${KEYSTORE}" ]; then
  echo "--- generating ${KEYSTORE} ---"
  keytool -genkeypair \
    -keystore "${KEYSTORE}" -storepass android \
    -alias androiddebugkey -keypass android \
    -dname 'CN=Android Debug,O=Android,C=US' \
    -keyalg RSA -keysize 2048 -validity 10000 -noprompt
fi

# ── 5c. apksigner sign + verify ─────────────────────────────────────────────
SIGNED_APK="${WORK_DIR}/app-release-signed.apk"
echo "--- apksigner sign ---"
"${APKSIGNER}" sign \
  --ks "${KEYSTORE}" --ks-pass pass:android --key-pass pass:android \
  --ks-key-alias androiddebugkey \
  --out "${SIGNED_APK}" "${ALIGNED_APK}"
echo "--- apksigner verify ---"
"${APKSIGNER}" verify "${SIGNED_APK}"
echo "apksigner verify: OK (exit 0)"

# ── 6. gates ────────────────────────────────────────────────────────────────
LISTING="${WORK_DIR}/unzip-l.txt"
BADGING="${WORK_DIR}/badging.txt"
unzip -l "${SIGNED_APK}" > "${LISTING}"
"${AAPT2}" dump badging "${SIGNED_APK}" > "${BADGING}"

if grep -qE 'lib/(x86_64|x86|armeabi-v7a)/' "${LISTING}"; then
  echo "FATAL: final APK still carries foreign ABIs:"
  grep -E 'lib/(x86_64|x86|armeabi-v7a)/' "${LISTING}"
  exit 1
fi
grep -qF "native-code: 'arm64-v8a'" "${BADGING}" || {
  echo "FATAL: badging does not report native-code: 'arm64-v8a'. Badging tail:"
  grep native-code "${BADGING}" || echo "(no native-code line at all)"
  exit 1
}
"${APKSIGNER}" verify "${SIGNED_APK}" >/dev/null 2>&1 || { echo "FATAL: apksigner verify failed"; exit 1; }

# ── 7. publish to workspace root under the canonical name ───────────────────
WORKSPACE_ROOT="$(cd -- "${PROJECT_ROOT}/.." && pwd)"
FINAL_APK="${WORKSPACE_ROOT}/Township-of-Tomorrow_v${VERSION_NAME}-android-arm64.apk"
cp -f "${SIGNED_APK}" "${FINAL_APK}"

echo
echo "=== FINAL arm64 build summary ==="
echo "file        : ${FINAL_APK}"
echo "size        : $(stat -c %s "${FINAL_APK}") bytes ($(du -h "${FINAL_APK}" | cut -f1))"
echo "sha256      : $(sha256sum "${FINAL_APK}" | cut -d' ' -f1)"
echo "native-code : $(grep -m1 '^native-code:' "${BADGING}")"
echo "ab-is       : $(grep -m1 '^application-label' "${BADGING}")"
echo "gates       : unzip-list clean · badging arm64-v8a OK · apksigner verify OK"
echo "keystore    : ${KEYSTORE} (debug, storepass/keypass 'android')"
echo "==============================="
