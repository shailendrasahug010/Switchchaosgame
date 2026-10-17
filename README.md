# The Chaos Switch

A funny, colorful 3D party game for 2–4 players, ages 9–12. Everyone races
through a goofy mission — grab a birthday cake, mash buttons, bounce along a
course — while **chaos events** randomly flip the rules: the floor turns to
ice, gravity goes soft, controls reverse, and more. Built with
[Godot 4](https://godotengine.org/) and GDScript. Android-first (touch
controls, landscape), also runs on desktop with a keyboard.

This is a real, playable prototype, not a concept document. Everything below
has actually been run in Godot by the people building it — see
[docs/TESTING.md](docs/TESTING.md) for what was checked and what wasn't.

## What's in the box

- **Three modes**: Cake Dash (carry the cake to the table), Button Mayhem
  (mash the glowing button fastest), Bounce Race (reach the finish line).
- **Chaos events**: eight rule-switches (Slippery Mode, Moon Mode, Reverse
  Mode, Sticky Mode, Tiny Mode, Giant Mode, Bounce Mode, Penguin Mode)
  announced with a countdown before they start and a toast when they end.
  The event system supports any number of events — eight ship today.
- **2–4 players**: humans on one device (split focus, not split-screen —
  see Known Limitations) plus CPU "buddies" filling empty seats.
- **Touch and keyboard**: on-screen joystick and big buttons on
  Android/touch devices; WASD/arrows + keyboard on desktop, two people can
  share one keyboard.
- **Four characters** with unlockable cosmetic accessories earned by
  playing (no purchases, no loot boxes — see Child Safety below).
- **Local save** of unlocked cosmetics and settings only.
- **Private-room online play** (proof of concept) — see
  [docs/ONLINE_MULTIPLAYER_PLAN.md](docs/ONLINE_MULTIPLAYER_PLAN.md) for
  what's built, what's missing, and what it would take to ship.

## Child safety and privacy

- No purchases, no loot boxes, no ads, no public chat or messaging of any
  kind — the online lobby uses room codes shared out-of-band (parents read
  the code to each other), never a friends list or text chat.
- No account system and no personal data collection beyond a chosen
  nickname and character, stored locally on the device.
- A simple arithmetic question ("what's 7 × 8?") gates the one menu a
  grown-up should confirm (clearing the save), so a young child doesn't
  trigger it by accident.
- This is **not** a legal compliance claim. Before any public release, an
  adult must review the app against Google Play Families Policy, COPPA, and
  any applicable local law (see the Play readiness notes in
  [docs/ONLINE_MULTIPLAYER_PLAN.md](docs/ONLINE_MULTIPLAYER_PLAN.md) and
  [docs/ANDROID_BUILD.md](docs/ANDROID_BUILD.md)).

## Requirements

- [Godot 4.7.x](https://godotengine.org/download) (built and tested against
  **4.7.2 stable**, standard build — not .NET). The project uses GDScript
  only, so any 4.7.x editor should open it.
- No other runtime dependencies to **play** the game. Compiling sounds or
  building an Android package needs extra tools — see below.

## Running it (editor)

1. Install Godot 4.7.x from godotengine.org.
2. Open Godot, choose **Import**, and select this folder's `project.godot`.
3. Press **F5** (Run Project), or click the play button.

That's the whole setup. The main menu opens; pick a mode, add players, go.

## Running it from the command line

These are the exact commands used throughout development. Run them from the
repository root with `godot` on your `PATH` (on Windows, use the full path
to `Godot_v4.7.2-stable_win64.exe`, or `godot4` if that's how you installed
it on Linux).

```bash
# Normal play, opens the main menu
godot --path .

# Jump straight into a round (handy for a quick check)
#   --quick=cake_dash | button_mayhem | bounce_race
#   --humans=N --cpus=N   who's playing (total must be 2-4)
#   --seed=1234           repeatable chaos-event picks, for testing
#   --no-chaos             play without rule switches
#   --time=45              shorter round, for testing
godot --path . -- --quick=cake_dash --humans=1 --cpus=3 --seed=1 --time=45

# Headless (no window) — used by the automated tests and CI-style checks
godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn

# Static project check (scenes, autoloads, chaos library wiring)
godot --headless --path . -s tools/check_project.gd
```

All command-line options are documented at the top of
`scripts/core/boot.gd`.

## Running a pre-built binary

If you'd rather not install the editor, exported builds are in `build/`
(these are **debug** builds made for testing, not a store release — see
[docs/ANDROID_BUILD.md](docs/ANDROID_BUILD.md) for what a release needs):

- **Windows**: `build/windows/TheChaosSwitch.exe` — double-click, or
  `TheChaosSwitch.console.exe` for one with a visible console/log window.
- **Linux**: there's no exported desktop binary in this repo yet (only the
  headless room server — see below); run from the editor with F5, or export
  one yourself with **Project → Export → Linux/X11**.
- **Android**: `build/android/the-chaos-switch-debug.apk` — install with
  `adb install build/android/the-chaos-switch-debug.apk`, or copy the file
  to a phone and open it (you'll need "install from unknown sources" since
  it isn't from a store). This is a **debug-signed** APK — Android will
  show an "insecure" warning on install, which is expected for a debug
  build and would go away with a proper release signature (see the build
  guide).

## Running the tests

```bash
# Full automated test suite (scene-based, deterministic, ~60-90 seconds)
godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn

# Run only tests whose name matches a filter
godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --filter=chaos

# Static project check (catches missing scenes/wiring without running them)
godot --headless --path . -s tools/check_project.gd

# Online multiplayer test: a real room server plus several headless
# "phones" talking over localhost UDP. Takes a few minutes (rounds run in
# real time, shortened to 30s each).
godot --headless --path . -s tools/net_sync_test.gd
```

See [docs/TESTING.md](docs/TESTING.md) for the full checklist, what each
test actually covers, and the known limitations found while testing.

## Project layout

```
scenes/          .tscn scenes: arenas, menus, UI, props
scripts/
  autoload/      singletons: GameState, AudioManager, InputSetup, Router
  core/          modifier stack, procedural mesh/material helpers
  chaos/         ChaosEvent resources + ChaosManager (the rule-switch system)
  modes/         the three game modes (each: mode script + arena builder)
  match/         MatchController, MatchSetup, scoring
  player/        player character, input sources (human + CPU bot)
  net/           online play: protocol, room server, client sync
  ui/            HUD, menus, widgets
data/chaos_events/  the eight ChaosEvent .tres resources
assets/          fonts (OFL-licensed), generated audio, icons
tests/           automated tests (TestCase-based) + the test runner scene
tools/           build/export/check/screenshot/test scripts (not shipped)
docs/            this project's documentation (build guide, testing, etc.)
```

## Documentation

- [docs/ANDROID_BUILD.md](docs/ANDROID_BUILD.md) — exact steps and SDK
  versions to build an Android APK/AAB, what was and wasn't possible to
  verify in this environment, and what a Play Store release needs.
- [docs/TESTING.md](docs/TESTING.md) — the testing checklist, what's
  automated vs. manually checked, and every known limitation.
- [docs/ONLINE_MULTIPLAYER_PLAN.md](docs/ONLINE_MULTIPLAYER_PLAN.md) — how
  private-room online play works today, its gaps (encryption above all),
  alternative approaches considered, and what shipping it for real needs.
- [docs/COST_AND_EFFORT_ESTIMATE.md](docs/COST_AND_EFFORT_ESTIMATE.md) — a
  realistic estimate of remaining work and what hosting online play would
  cost, based on measurements taken from this build.

## License / credits

Original code and procedurally-generated art/audio for this project. The
UI font is [Fredoka](https://fonts.google.com/specimen/Fredoka)
(SIL Open Font License 1.1) — see `assets/fonts/Fredoka-OFL.txt`. No
third-party audio samples, art packs, or SDKs are bundled.
