# NOVA PHOTOS — Toolchain Report

**Date:** 2026-11-22 (verified 06:04–07:30 UTC / 11:04–12:30 PKT)
**Host:** Ubuntu 24.04.5 LTS, Linux 7.0.0-44-generic, x86_64, 4 CPUs, ~8 GB RAM
**Mission:** Flutter Android app, built in this Linux VM. No money spent, no sign-ins, no credentials used.

## TL;DR — verdict

**Toolchain is installed and verified working for `flutter create` + `flutter analyze`.**
Flutter 3.50.1 / Dart 3.14.0, Android SDK 36 + build-tools 36.0.0, JDK Temurin 17.0.20.1, Gradle 8.14.3.
`flutter analyze --no-pub` on a throwaway project: **"No issues found!"**

**Two real blockers to know about (both the same root cause — the VM's authenticated egress proxy):**

1. **Dart's `pub` client cannot reach pub.dev through the proxy.** Any Flutter/Dart command that runs an *online* `pub get` hangs forever (observed 32 min idle, 0 CPU, on an established proxy connection). Workarounds that work: `dart pub get --offline` and `flutter analyze --no-pub` / `flutter create --no-pub`. Any future build step that needs a package not already in the local pub cache will need the offline route or a proxy fix.
2. **`sdkmanager` cannot fetch the remote repository** (same proxy; Java `HttpURLConnection` fails to tunnel). So no SDK component can be installed/updated via `sdkmanager`, and `flutter doctor --android-licenses` fails. Workaround that works: download the component zips directly with `curl` from `dl.google.com` and unzip them into the SDK (done for platform-36, build-tools 36.0.0, platform-tools 37.0.3 — see below).

**Not attempted (per task):** no APK build yet, no Gradle daemon run. The Gradle daemon handshake is already known to fail in this VM from an earlier project — the first real `flutter build apk` is expected to hit that and will need its own session.

---

## 1. Paths and environment

| Variable | Value |
|---|---|
| Flutter SDK | `~/workspace/nova-photos/research/flutter-sdk/flutter` |
| Flutter tarball (kept) | `~/workspace/nova-photos/research/flutter-sdk/flutter_linux_3.50.1-stable.tar.xz` (1.4 GB) |
| `ANDROID_HOME` / `ANDROID_SDK_ROOT` | `~/workspace/android-sdk` |
| `JAVA_HOME` | `~/workspace/android-sdk/jdk-17.0.20.1+1` |
| `PATH` (session only) | `$FLUTTER_SDK/bin:$PATH` — not persisted to any shell rc file |

Session setup for any future shell in this VM:

```bash
export PATH="$HOME/workspace/nova-photos/research/flutter-sdk/flutter/bin:$PATH"
export JAVA_HOME=$HOME/workspace/android-sdk/jdk-17.0.20.1+1
export ANDROID_HOME=$HOME/workspace/android-sdk
export ANDROID_SDK_ROOT=$ANDROID_HOME
```

Note: the shell runs as **root**; Flutter prints this warning on every invocation (harmless):
`Woah! You appear to be trying to run flutter as root. We strongly recommend running the flutter tool without superuser privileges.`

## 2. Flutter SDK download

- Source: `https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json` → current stable **3.50.1**, hash `ae9b586f34a8443573f82ef57c3bf914a908cbf7`
- Tarball: `https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.50.1-stable.tar.xz` (1,448 MB)
- SHA-256 verified: `4ad17fc8462fbcef2ba19ff4a78c0a16b7147fde1add8578e267ea62cdb92678` — **matches** the releases JSON.
- Download speed: ~0.4–4 MB/s via curl (first attempt at ~376 KB/s was killed after ~1 min and retried; the successful run averaged ~3.9 MB/s, ~6.5 min total).
- Mirrors speed-tested (2 MB ranged fetch) and rejected: TUNA (`mirrors.tuna.tsinghua.edu.cn`) 404; `storage.flutter-io.cn` ~9 KB/s; USTC 403; NJU ~534 KB/s. `storage.googleapis.com` was fastest (~812 KB/s in the probe, faster in the real run).
- Extraction: `tar xf` completed but exited code 2 with thousands of `Cannot change ownership to uid 1000, gid 1000: Operation not permitted` warnings — **harmless**: the tarball records uid/gid 1000 and the shell runs as root in a restricted mount. All files extracted; `flutter/bin/flutter` and `flutter/bin/cache/dart-sdk/bin/dart` are present and executable.
- Analytics disabled: `flutter config --no-analytics` → `Analytics reporting disabled.`

## 3. Versions verified

`flutter --version` (full output saved in `research/flutter-version.txt`):

```
Flutter 3.50.1 • channel stable • https://github.com/flutter/flutter.git
Framework • revision ae9b586f34 (3 days ago) • 2026-11-18 17:01:07 -0800
Engine • hash 51379e6df48ea8ee7205623b90fe66491cad8df3 (revision 4d35714800) (4 days ago) • 2026-11-18 01:50:07.000Z
Tools • Dart 3.14.0 • DevTools 2.61.0
```

| Component | Version |
|---|---|
| Flutter (stable) | 3.50.1, framework rev `ae9b586f34`, engine rev `4d35714800` |
| Dart | 3.14.0 |
| DevTools | 2.61.0 |
| JDK | OpenJDK Temurin **17.0.20.1+1** (`javac 17.0.20.1`, 64-Bit Server VM) |
| Gradle (bundled in SDK dir) | **8.14.3** (Build time 2025-07-04, Kotlin 2.0.21) |
| Android SDK | 36.0.0 (doctor reports "Android SDK version 36.0.0") |
| adb / platform-tools | 1.0.41 / **37.0.3** |
| cmake (host) | 3.28.3, pkg-config 1.8.1 |

## 4. Android SDK components present

`sdkmanager --list_installed` (works — local read only):

```
build-tools;34.0.0   | 34.0.0 | Android SDK Build-Tools 34     | build-tools/34.0.0
build-tools;36.0.0   | 36.0.0 | Android SDK Build-Tools 36     | build-tools/36.0.0
platforms;android-34 | 3      | Android SDK Platform 34, rev 3 | platforms/android-34
platforms;android-36 | 2      | Android SDK Platform 36, rev 2 | platforms/android-36
```

Plus `cmdline-tools/latest` (sdkmanager, avdmanager, lint, etc.), `platform-tools/` (adb 37.0.3, fastboot), `gradle-8.14.3/`, `jdk-17.0.20.1+1/`, `licenses/`, and `dl/` (source zips, see §6).

**What was missing and added during this session:** Flutter 3.50 requires Android SDK 36 — only android-34 was present, so the first `flutter doctor -v` failed the Android toolchain with:

```
✗ Flutter requires Android SDK 36 and the Android BuildTools 28.0.3
```

`platform-36` and `build-tools 36.0.0` were installed from direct `dl.google.com` downloads (sdkmanager network is broken, §7). `adb` was also missing (`✗ Android SDK file not found: adb.`) — fixed by installing platform-tools 37.0.3 the same way.

**Not present (and not needed for an Android-only app):** no emulator images, no Chrome, no `clang++`/`ninja`/GTK 3 dev libs (Linux desktop toolchain), no iOS tooling. `flutter doctor` flags Chrome and Linux toolchain as `[✗]` — irrelevant for this mission.

## 5. `flutter doctor -v` — final state

Full output saved in `research/flutter-doctor-final.txt`. Summary:

```
[✓] Flutter (Channel stable, 3.50.1, on Ubuntu 24.04.5 LTS 7.0.0-44-generic, locale en_US)
[✓] Proxy Configuration (HTTP_PROXY is set; NO_PROXY contains localhost)
[✓] Connected device (1 available) — Linux (desktop) • linux-x64
[!] Android toolchain - develop for Android devices (Android SDK version 36.0.0)
      • Platform android-36, build-tools 36.0.0
      • Java binary at: .../jdk-17.0.20.1+1/bin/java (Temurin-17.0.20.1+1)
      ✗ Android license status unknown.
        Run `flutter doctor --android-licenses` to accept the SDK licenses.
[✗] Chrome - develop for the web (Cannot find Chrome executable at google-chrome) — not needed
[✗] Linux toolchain - develop for Linux desktop (clang++/ninja/GTK missing) — not needed
[☠] Network resources (the doctor check crashed)
      ✗ Exception: Network resources exceeded maximum allowed duration of 0:04:30.000000
```

Notes on the two non-green items that matter:

- **"Android license status unknown"** — cosmetic here, see §7. The license files exist with the standard accepted hashes (§7); Gradle checks those files directly, so builds are not blocked by this. `flutter doctor --android-licenses` cannot fix it in this VM (it shells out to the broken sdkmanager).
- **"Network resources" check crash** — same Dart/proxy root cause as §7: doctor's network probe hangs and is killed after 4m30s. It makes `flutter doctor` slow (one run took 4m40s); other runs finished in ~8s without that check firing.

## 6. Disk usage

| Path | Size |
|---|---|
| `~/workspace/nova-photos/research/flutter-sdk/` (tarball + extracted SDK) | 3.7 GB |
| `~/workspace/nova-photos/research/flutter-sdk/flutter` (extracted SDK) | 2.3 GB |
| `~/workspace/android-sdk/` total | 2.3 GB |
| — `gradle-8.14.3/` | 489 MB |
| — `dl/` (source zips) | 466 MB |
| — `jdk-17.0.20.1+1/` | 318 MB |
| — `build-tools/` (34.0.0 + 36.0.0) | 297 MB |
| — `cmdline-tools/` | 294 MB |
| — `platforms/` (android-34 + android-36) | 261 MB |
| — `jdk17.tar.gz` | 185 MB |
| — `platform-tools/` | 22 MB |
| `~/.pub-cache/` (created by offline pub gets) | ~tens of MB |
| Free disk after all work | **103 GB** of 150 GB (was 106 GB before; toolchain added ~4.6 GB) |

## 7. Blockers and exact errors

### 7a. Dart `pub` cannot reach pub.dev through the VM proxy — HANGS (biggest blocker)

The VM routes egress through an authenticated HTTP proxy (`http_proxy`/`https_proxy` env). `curl` through it works fine (pub.dev answered in 0.87s). **Dart's HTTP client does not** — it opens a connection to the proxy and then stalls forever.

Evidence:

- First `flutter doctor -v` hung 32+ minutes on this subprocess (0 CPU, futex wait, one ESTABLISHED socket to the proxy at `198.19.0.1:3128`):
  `dart pub --suppress-analytics --directory workspace/nova-photos/research/flutter-sdk/flutter/packages/flutter_tools get --example`
  After killing that subprocess, doctor aborted with:
  ```
  Failed to update packages.
  #0      throwToolExit (package:flutter_tools/src/base/common.dart:36:3)
  #1      _DefaultPub._runWithStdioInherited (package:flutter_tools/src/dart/pub.dart:533:7)
  ...
  #3      PubDependencies.update (package:flutter_tools/src/flutter_cache.dart:127:5)
  ```
- Manual repro with `dart pub --verbose get --example` progressed through local version-solving, then stalled at:
  ```
  IO  : Get versions from https://pub.dev/api/packages/test.
  IO  : HTTP GET https://pub.dev/api/packages/test
      | Accept: application/vnd.pub.v2+json
      | user-agent: Dart pub 3.14.0
  ```
  (killed by a 90s timeout; nothing after that line.)
- `flutter analyze` (plain, no flags) also hangs on its implicit online `pub get` — killed by a 110s timeout after printing only `Resolving dependencies...` / `Failed to update packages.`

**Workarounds verified working:**

- `dart pub get --offline` — resolves entirely from the SDK's `.pub-preload-cache` + `~/.pub-cache`; completes in ~1s. Used to fix the flutter_tools stamp (`dart pub get --offline --example` in `flutter/packages/flutter_tools` → `Got dependencies!`), after which `flutter doctor -v` completes in ~8s.
- `flutter create --no-pub` + `dart pub get --offline` in the project, then `flutter analyze --no-pub`.

**Consequence for the real project:** every `flutter` command that triggers an online `pub get` will hang. The NOVA PHOTOS project must keep all its dependencies resolvable from the local cache, or use `--offline` / `--no-pub` flags everywhere. If a new package is needed that is not in the cache, `pub get` will hang — that needs a proxy fix for Dart (out of scope here) or a vendored/cached copy of the package.

### 7b. `sdkmanager` cannot reach the remote repository — same proxy, different symptom

Any sdkmanager operation that fetches the remote repo fails immediately with:

```
Exception in thread "main" java.util.NoSuchElementException
	at java.base/java.util.StringTokenizer.nextToken(StringTokenizer.java:347)
	at java.base/sun.net.www.protocol.http.HttpURLConnection.doTunneling0(HttpURLConnection.java:2277)
	at java.base/sun.net.www.protocol.http.HttpURLConnection.doTunneling(HttpURLConnection.java:2222)
	at java.base/sun.net.www.protocol.https.AbstractDelegateHttpsURLConnection.connect(AbstractDelegateHttpsURLConnection.java:187)
	...
	at com.android.sdklib.tool.sdkmanager.SdkManagerCli.main(SdkManagerCli.java:48)
```

Java's `HttpURLConnection` cannot tunnel through the authenticated proxy (fails parsing the proxy response). Retried with explicit JVM proxy properties (`-Dhttps.proxyHost/-Dhttps.proxyPort/-Dhttps.proxyUser/-Dhttps.proxyPassword` via `JDK_JAVA_OPTIONS`) — **same failure**. Total time spent on this: ~5 min, then stopped per instructions. `sdkmanager --list_installed` works (local only).

**Workaround verified working:** download component zips with `curl` from `dl.google.com/android/repository/` (repository index `repository2-1.xml`) and unzip into the SDK. Used for:

| Component | Zip | Installed to |
|---|---|---|
| Platform android-36 rev 2 | `platform-36_r02.zip` (63 MB, sha1 `2c1a80dd4d9f7d0e6dd336ec603d9b5c55a6f576`) | `platforms/android-36/` (135 MB) |
| Build-tools 36.0.0 | `build-tools_r36_linux.zip` (61 MB, sha1 `b0b6376977657e8ad9b969bacf4093601da2c6fb`) | `build-tools/36.0.0/` (147 MB; zip's inner dir is named `android-16`, renamed on install) |
| Platform-tools 37.0.3 | `platform-tools_r37.0.3-linux.zip` (9.2 MB) | `platform-tools/` (adb 1.0.41 verified: `adb --version` → `Android Debug Bridge version 1.0.41`, `Version 37.0.3-16887417`) |

Zips kept in `~/workspace/android-sdk/dl/` alongside the pre-existing `bt34.zip`, `platform34.zip`, `gradle.zip`.

### 7c. Android licenses — files present, doctor says "unknown"

`~/workspace/android-sdk/licenses/` contains:

- `android-sdk-license`: `8933bad161af4178b1185d1a37fbf41ea5269c` and `79120722343a6f314e0719f121dda3f2b742a0fa` (the standard current accepted hashes)
- `android-sdk-preview-license`: `84831b9409646a918e30573bab4c8cdd998d`

`flutter doctor --android-licenses` fails because it runs the broken sdkmanager (§7b):

```
Android sdkmanager tool was found, but failed to run (.../cmdline-tools/latest/bin/sdkmanager): "exited code 1".
```

The license files themselves are what Gradle checks at build time, so this should not block an APK build. If a build ever complains about licenses, the fix is to add the missing hash line to `licenses/android-sdk-license`, not to fight sdkmanager.

## 8. Verification: throwaway project

```bash
cd /tmp
flutter create --no-pub --project-name nova_toolchain_test nova_toolchain_test
# Creating project nova_toolchain_test... Wrote 131 files. All done!
cd nova_toolchain_test
dart pub get --offline        # Changed 31 dependencies! (exit 0)
flutter analyze --no-pub      # Analyzing nova_toolchain_test... No issues found! (ran in 16.9s)
```

- `flutter create` (with `--no-pub`): **PASS**, 131 files.
- `dart pub get --offline`: **PASS**.
- `flutter analyze --no-pub`: **PASS — No issues found!**
- Plain `flutter analyze` (no flags): **FAILS/HANGS** — implicit online pub get (§7a).
- Project deleted afterwards (`rm -rf /tmp/nova_toolchain_test`); nothing remains in `/tmp` from this test. (Note: `/tmp` was also wiped once by a service restart mid-task; the test was re-run from scratch and passed.)

## 9. Not done / open risks for the build phase

1. **No APK build attempted** (per task). First `flutter build apk` is untested; the Gradle daemon handshake is known to fail in this VM from an earlier project — expect that to be the next fight, and budget one careful attempt, not hours.
2. **No emulator / device.** No AVD images installed; no Android device is connected. APKs can be built and installed later via `adb` (now present) or transferred to the phone.
3. **Offline-only pub.** Any new dependency not already in `~/.pub-cache` / the SDK preload cache will hang `pub get` (§7a). Keep the dependency list minimal and pre-seeded.
4. **`flutter doctor` is slow when its Network resources check fires** (4m30s timeout, §5). Use `flutter doctor -v` sparingly; the Android toolchain section is what matters.
5. **Chrome / Linux desktop toolchain missing** — only relevant if the mission ever targets web/desktop; not needed for Android.
6. **Running as root** — Flutter warns on every run; harmless so far.

## 10. Files produced by this session

- `~/workspace/nova-photos/research/toolchain.md` — this file
- `~/workspace/nova-photos/research/flutter-version.txt` — `flutter --version` output
- `~/workspace/nova-photos/research/flutter-doctor-final.txt` — full final `flutter doctor -v` output
- `~/workspace/nova-photos/research/flutter-sdk/flutter/` — Flutter 3.50.1 SDK (extracted)
- `~/workspace/nova-photos/research/flutter-sdk/flutter_linux_3.50.1-stable.tar.xz` — SDK tarball (kept for re-extraction)
- `~/workspace/android-sdk/platforms/android-36/`, `~/workspace/android-sdk/build-tools/36.0.0/`, `~/workspace/android-sdk/platform-tools/` — newly installed SDK components
- `~/workspace/android-sdk/dl/platform-36_r02.zip`, `build-tools_r36_linux.zip`, `platform-tools_r37.0.3-linux.zip` — source zips
