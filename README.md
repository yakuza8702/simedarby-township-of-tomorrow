# Township of Tomorrow (Android)

Flutter app for a gated-community recycling programme. Residents scan waste
with an on-device AI classifier and log what was collected. They attach proof
photos, report problems with bins or dumping, pass reusable items along on the
Circular Hub, and chat on the community board. Everything works offline; the
scan pipeline never talks to a server.

## Who it is for

| Audience | What they get |
|---|---|
| Residents | Scan, collection log, proof photos, hazard reports, Circular Hub, community board |
| Operator and command centre staff | A gated tier: the Operator dashboard and Command centre open only through a staff switch in Profile, with separate routes (`/operator`, `/command`) |

The staff switch lives in Profile, so without it `/operator` and `/command`
stay closed and a resident reaches neither dashboard. One switch, two extra
routes, no other gate.

## Get the app

Two options:

1. **Download the release APK.** A GitHub Actions workflow in this repo builds
   an arm64 APK artefact on every push. Open the Actions tab, pick the latest
   run of the workflow, and download the APK artefact from the run page.
2. **Build it locally.**

Take the first option when you only want to install the app. The second is
what you want after touching the source, and the exact command sits below.
Both paths end at the same release build.

```bash
flutter pub get
flutter build apk --release \
  --target-platform android-arm64 \
  --android-skip-build-dependency-validation \
  -Ptownship.abiFilters=arm64-v8a \
  -Pandroid.builder.sdkDownload=false
```

Quirk when running Gradle directly instead of the Flutter CLI:

```
cd android && ./gradlew assembleRelease ...
  -Ptownship.abiFilters=arm64-v8a
  -Pdisable-abi-filtering=true
  -Ptree-shake-icons=true
```

The three flags come straight from the v0.4.1 size ledger in
`test-folder/logs/arm64-size-report-v041.md`. Without them the release APK
ships all three ABIs (192 MB instead of 96 MB) and skips icon tree-shaking.
That happens because the Flutter plugin clears `abiFilters` and the raw Gradle
path does not shake icons by default. In practice, `township.abiFilters` alone
is a measured no-op.

## Test on the emulator in this workspace

A release arm64 APK cannot run on the local x86_64 emulator, so the debug x86
variant comes first:

```bash
flutter build apk --debug --target-platform android-x64 \
  -Ptownship.abiFilters=x86_64 --android-skip-build-dependency-validation
```

That debug build is what the local emulator loads, so keep the release command
above for anything you intend to hand out.

Then boot an emulator and install:

```bash
android emulator create medium_phone
```

One profile is enough; the rest of this section runs against `medium_phone`.

Use the `medium_phone` profile (x86_64, Android 16, API 36). With the bundled
cmdline-tools, `avdmanager create avd` is unreliable and fails with "Package
path is not valid". The new `android emulator` CLI is the documented path.

The `/tmp` quirk: `/tmp` on this container is a 2 GB read-only tmpfs, yet
Gradle's daemon, Kotlin and AGP all try to write to it. Set these two
variables before any build or AVD run so the JVM and emulator stay on the
workspace volume:

```bash
TMPDIR=/workspace/.agent-tmp
ANDROID_AVD_HOME=/workspace/.android/avd
```

Both keep the JVM and the AVD writing to the workspace volume instead of the
read-only `/tmp`.

The Java daemon ignores `TMPDIR`, so pass the same directory twice when you
call Gradle directly:

```
-P"org.gradle.jvmargs=-Xmx2g -XX:MaxMetaspaceSize=512m -Djava.io.tmpdir=/workspace/.agent-tmp/jvm"
-Dorg.gradle.jvmargs=<same string again>
```

Boot takes a few minutes on KVM. Wait for `sys.boot_completed=1`, then wait
another 30 to 60 seconds before installing, because the launcher comes up
later than the boot flag. Install with `adb push` plus `pm install`. A
streamed install fails silently on this emulator.

## Theme toggle

Profile → Appearance → "Theme · System default", then pick Light or Dark in
the dialog. The choice is stored in the app's own persistence layer
(`app_flutter/township_state.json`) and survives a force stop and relaunch.
After that relaunch, Profile → Appearance still shows the theme you picked.

## Privacy

All AI inference runs on this phone. Scan photos stay on the device and are
never uploaded. Only the Circular Hub shares anything, and it always asks
first. See the Privacy card on the Profile screen for the exact wording shown
to residents.
