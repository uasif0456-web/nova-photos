# NOVA PHOTOS — Build Instructions

## Status

**Code complete. Local APK build does NOT work in this VM; cloud build pending repo creation.**

- `flutter analyze`: clean. `flutter test`: 82 passed, 0 failed (plus 1 live smoke test, passed against the demo server).
- Local `flutter build apk --release` fails in this VM at the Gradle daemon step: `Could not dispatch a message to the daemon.` (Gradle task `assembleRelease`, 10.4 s in). This is the same failure established earlier with the TuneWave project — the VM's Gradle daemon handshake fails regardless of project. A local workaround was attempted and exhausted:
  - The Gradle wrapper could not download its distribution (Java SSL failure through the egress proxy); the distribution (Gradle 9.5.0) was downloaded via curl and the wrapper pointed at the local file, which got past the download — then the daemon dispatch failed anyway.
  - The wrapper properties file was restored to the standard `https://services.gradle.org/distributions/gradle-9.5.0-all.zip` URL, so the cloud build is unaffected.
- **No local APK exists. No checksum is claimed.** The APK is built by the GitHub Actions workflow (`.github/workflows/build-apk.yml`) once the repository exists.

## Cloud build (the supported route)

1. **Create the repository** (repo owner, one time): on GitHub, create `nova-photos` under `uasif0456-web`, and grant the Muse GitHub App access to it. (Muse's GitHub App cannot create repositories — the owner must create it.)
2. **Push this workspace** to the repo's `main` branch (all files except the `.gitignore`d research clones and SDK).
3. The workflow runs on every push to `main` and on manual dispatch:
   - Sets up Java 17 (Temurin) and Flutter 3.50.1 (stable, cached).
   - Runs `flutter pub get`, `flutter analyze`, `flutter test`.
   - Runs `flutter build apk --release`.
   - Computes the SHA-256 of `app-release.apk` and uploads both the APK and the `.sha256` file as the `nova-photos-apk` artifact (90-day retention).
4. **Download the APK** from the Actions run's artifacts, verify the checksum (`sha256sum app-release.apk` must match the `.sha256` file), then install on the phone.

## Local development build (for a machine where Gradle works)

Prerequisites: Flutter 3.50.1, Dart 3.14.0, Android SDK 36 (platforms android-34/36, build-tools 34/36), JDK 17.

```sh
export PATH="$HOME/workspace/nova-photos/research/flutter-sdk/flutter/bin:$PATH"
export ANDROID_HOME=$HOME/workspace/android-sdk
export ANDROID_SDK_ROOT=$HOME/workspace/android-sdk
export JAVA_HOME=$HOME/workspace/android-sdk/jdk-17.0.20.1+1

cd app
flutter pub get
flutter analyze
flutter test
flutter build apk --release        # output: build/app/outputs/flutter-apk/app-release.apk
flutter build apk --debug          # debug variant, if needed
```

Verify the output before claiming a build:

```sh
ls -la build/app/outputs/flutter-apk/app-release.apk
sha256sum build/app/outputs/flutter-apk/app-release.apk
```

## Versioning

- Application ID: `com.novaphotos.app`
- Version: `1.0.0+1` (see `app/pubspec.yaml`)
- Minimum Android SDK: see `app/android/app/build.gradle.kts` (Flutter default for 3.50; target SDK 36)
- Permissions declared in `app/android/app/src/main/AndroidManifest.xml` (see `SECURITY.md` for the list and why each is needed)

## Signing (release)

The cloud workflow currently builds an **unsigned** release APK (Flutter default `flutter build apk --release` without a keystore signs with the debug key in CI — installable, but not suitable for Play Store distribution). Before any public release, add a release keystore as GitHub Actions secrets (`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`) and wire `android/key.properties` in the workflow. This is documented as remaining work, not done, because no keystore may be created or stored without the owner's involvement.
