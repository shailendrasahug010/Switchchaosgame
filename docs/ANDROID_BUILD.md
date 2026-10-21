# Android build guide

This covers building an Android package from this project: what already
works, what a real device/Play Store release needs, and exactly what was
and wasn't possible to verify in the sandbox this project was built in.

## What's already true today

A **debug APK** builds successfully in this project with nothing more than
Godot, a JDK, and the Android `build-tools`/`platform-tools` packages (no
full SDK, no NDK, no Gradle needed — see "Why the debug build needs so
little" below). `build/android/the-chaos-switch-debug.apk` in this repo was
built this way and verified:

- Installs and runs (it's the same debug build format Godot's "Install &
  run" button in the editor produces).
- Signed with the Android **debug key** (v2 and v3 signature schemes) —
  `apksigner verify` passes. This is normal for a debug build and expected
  to show an "app not verified" / developer warning on install.
- Manifest: `minSdkVersion=24`, `targetSdkVersion=36`, one permission
  (`android.permission.INTERNET`, needed for the private-room online
  mode), `debuggable=true`.
- Package ID `io.github.shailendrasahug010.chaosswitch`, version
  `0.1.0` (code `1`).

This was **not** run on a real Android device or emulator in this
environment — only exported and the resulting file inspected (signature
verification, manifest contents). Installing it on an actual phone or
tablet before shipping is still untested and should be the first thing
anyone picking this up does.

## Building it yourself

1. Install **Godot 4.7.x** (this project was built against 4.7.2 stable).
2. In Godot, go to **Editor → Manage Export Templates** and install the
   templates matching your exact Godot version (they must match exactly).
3. Install a JDK. Godot's official docs recommend **OpenJDK 17**, and note
   newer JDKs are also supported (this build was made with OpenJDK 21
   without issue).
4. Install the Android SDK components Godot's docs list for exporting
   (via Android Studio or the standalone `sdkmanager`):
   - `platform-tools` 35.0.0 or later
   - `build-tools;35.0.1`
   - `platforms;android-35`
   - `cmdline-tools;latest`
   - `cmake;3.10.2.4988404`
   - `ndk;28.1.13356709` (NDK r28b)

   In Godot's **Editor Settings → Export → Android**, set the Java SDK
   path and the Android SDK path to match where you installed them.
5. Open this project in Godot, go to **Project → Export**, select the
   **Android** preset (already configured — package name, permissions,
   architecture arm64-v8a, see `export_presets.cfg`), and click
   **Export Project** (unticking "Export With Debug" for a release build —
   see below first).

Command line, once the above is set up:

```bash
godot --headless --path . --export-debug "Android" build/android/the-chaos-switch-debug.apk
```

### Why the debug build needs so little

The Android preset has `gradle_build/use_gradle_build = false`, so Godot
packages the prebuilt engine binary from the export templates directly
into an APK rather than compiling an Android Gradle project. That only
needs `build-tools` (for `aapt`/`apksigner`) and `platform-tools` — not the
SDK platform, NDK, or Gradle itself. That's the path this sandbox could
actually exercise, since `platforms;android-35`, `cmdline-tools`, and the
NDK are not installed here (only `build-tools;33.0.2` and `platform-tools`
are present, left over from earlier Godot editor use) and the hosts that
serve them (`dl.google.com`, `maven.google.com`, `repo1.maven.org`) are not
reachable from this sandbox's network allowlist — confirmed by direct
connection attempts, not assumed.

A **Gradle build** (`gradle_build/use_gradle_build = true`) is what you get
if you need an Android App Bundle (`.aab`) instead of an APK, or any native
plugin. It needs the full SDK platform, the NDK, and Gradle (present on
this machine at `/opt/gradle` — Gradle 8.14.3 — but untested end-to-end
here because the SDK platform and NDK packages above couldn't be
downloaded). **This was not attempted or verified in this environment.**
If you have real internet access to Google's Maven repositories, it
should work the same way it does for any Godot 4.7 project — see
[Godot's Gradle build docs](https://docs.godotengine.org/en/4.7/tutorials/export/android_gradle_build.html).

## Release build (before this goes on a device that isn't yours, or onto Play)

The shipped debug APK is **not** suitable for distribution. Before giving
this to anyone outside the dev team:

1. **Generate a release keystore** (once — keep the file and the
   passwords somewhere safe; losing them means you can never update the
   app under the same package again):
   ```bash
   keytool -genkeypair -v -keystore release.keystore -alias chaos_switch \
       -keyalg RSA -keysize 2048 -validity 10000
   ```
2. In **Project → Export → Android**, fill in `keystore/release`,
   `keystore/release_user`, `keystore/release_password` with that file's
   path, alias, and password (or set the `GODOT_ANDROID_KEYSTORE_RELEASE_*`
   environment variables instead of editing the preset).
3. **Untick "Export With Debug"** and export again. The result will not
   have `debuggable=true` and will be signed with your key, not the shared
   debug key — check both with `apksigner verify --print-certs` and
   `aapt dump badging` before distributing.
4. For the Play Store specifically, Google requires an **Android App
   Bundle (`.aab`)**, not an APK, for new app uploads (and has since
   August 2021) — which means the Gradle build path above, not the debug
   build path this sandbox verified.
5. Bump `version/code` and `version/name` in the Android preset (and in
   `project.godot`) for each release you ship.

## Google Play readiness — what to check before publishing

**None of this is legal advice.** These are pointers to current Google
Play policy and the applicable law for an adult to review properly,
not a compliance claim about this project.

- **Target API level**: Play requires new apps and updates to target
  **Android 16 (API level 36)** as of **August 31, 2026**, with a
  one-time extension available to **November 1, 2026** for developers who
  request it in Play Console. As of this writing the original deadline
  has passed; this project's export preset already targets API 36
  (confirmed in the exported manifest above), so it's ahead of either
  date — but this is one setting, not a compliance review.
- **Closed testing requirement**: personal Play developer accounts
  created after **November 13, 2023** must run a closed test with at
  least **12 testers opted in for 14 consecutive days** before they can
  apply to publish to production. Budget real calendar time for this, not
  just build time.
- **One-time registration fee**: Google currently charges **US$25** to
  register a new Play developer account.
- **Play Families Policy** (required if the app targets or appeals to
  children, which this one does): no advertising ID or other
  identifiers that aren't strictly needed for a child-directed app, only
  self-certified "Families-safe" ad/analytics SDKs if you ever add any
  (**this project bundles none today**), a neutral age screen rather than
  one that nudges toward the "I'm older" option, and a privacy policy and
  Data Safety form that accurately describe what the app collects (today:
  nothing beyond a locally-saved nickname/character/settings — no
  accounts, no analytics, no ads).
- **COPPA** (US): the FTC's COPPA Rule amendments have a stated
  compliance date of **April 22, 2026**, which has already passed as of
  this writing — a real compliance review against the current rule (not
  an older summary of it) is needed before any US release aimed at or
  likely to attract children.
- **India DPDP Act**: phased rules include consent-manager provisions
  (around **November 13, 2026**) and children's-data-specific rules
  (around **May 13, 2027**) — worth checking if the app's expected
  install base includes users in India.
- None of the above has been implemented or reviewed against this
  project's actual code (privacy policy text, Data Safety form answers,
  age-screen copy) — only the technical facts stated (what data the app
  actually stores, what permissions it requests) have been verified
  directly against the code and the exported manifest.

## Known limitations (Android specifically)

- Only `arm64-v8a` is enabled in the export preset (covers effectively
  all Android devices sold since ~2018; `armeabi-v7a`/`x86`/`x86_64` are
  off to keep the APK smaller — turn them on in `export_presets.cfg` if
  you need to support older/x86 hardware).
- No AAB has been built or tested (see Gradle build, above).
- No release keystore exists in this repo (correctly — it shouldn't be
  committed). One must be generated by whoever owns the release.
- The debug APK has not been installed on physical hardware in this
  environment — touch controls, performance, and screen-size handling on
  a real device are unverified beyond what the headless test suite and
  rendered screenshots can check (see [TESTING.md](TESTING.md)).
