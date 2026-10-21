# Testing checklist and known limitations

This project has an automated test suite that actually runs the game logic
(not mocks) inside the Godot engine, plus a few manual/visual tools for
things automated tests can't judge (does it *look* right, does it *feel*
right on a touchscreen). This document says exactly what's covered by what,
what passed last time it was run, and — just as important — what hasn't
been checked at all.

## Running the automated suite

```bash
godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn
```

Last run on this build (after the Cake Dash pathfinding fix,
commit `1ab957e`): **77 passed, 0 failed**, in about a minute.
`godot --headless --path . -s tools/check_project.gd` (static scene/wiring
check) also passes clean: 96 scripts, 13 scenes, 12 resources checked, 19
cross-references resolved.

Both commands exit non-zero on failure, so they're CI-friendly as-is (there
is no CI configured in this repo yet — see Remaining Work in
[COST_AND_EFFORT_ESTIMATE.md](COST_AND_EFFORT_ESTIMATE.md)).

## What the 77 automated tests cover

| File | Tests | Covers |
|---|---|---|
| `test_chaos_events.gd` | 12 | Every chaos event individually, expiry/cleanup, overlapping events, exclusive groups (events that can't run together), scheduling rules, and the remote-command path used for online play. Runs against a real `PlayerCharacter` with scripted input, so it checks what a player would actually feel (e.g. "is slower" not just "the stat number is lower"). |
| `test_controls.gd` | 11 | Keyboard input end-to-end (key press → InputMap → character moves) and touch input end-to-end (touch → the on-screen `TouchControls` → character moves), plus Reverse Mode's effect on both. |
| `test_hud.gd` | 4 | Every chaos event gets an announcement card (icon, name, tip, countdown) before it starts, stays listed in the HUD while active, and shows a toast when it ends. |
| `test_layout.gd` | 3 | On-screen controls stay fully visible with no scrolling/clipping at three screen shapes: 16:9 phone (1280×720), 20:9 phone (2400×1080, scaled), 4:3 tablet (1024×768, scaled). |
| `test_match_flow.gd` | 5 | Full round lifecycle (intro → countdown → playing → finished → results), scoring, restart — **plus** the new regression test that CPU buddies in Cake Dash keep up with a human carrying the cake instead of getting stuck (5 seeds, asserts ≤8s total stand-still per buddy and ≤8 falls total — see the Cake Dash fix below). |
| `test_modes.gd` | 12 | Each mode's actual rules, played with scripted input: grabbing/helping/dropping/delivering the cake; pressing right vs. wrong buttons in Button Mayhem; racing, checkpoints, and falling in Bounce Race. Chaos events off unless a test explicitly turns them on. |
| `test_pause.gd` | 5 | Pausing freezes the timer, characters, obstacles, and chaos countdowns; resuming continues exactly where it stopped. |
| `test_progression.gd` | 13 | Local save data, earned cosmetic unlocks, and the fair-play scoring rules (e.g. that score only rewards positive play). |
| `test_screens.gd` | 9 | Every menu screen opens without errors and its main buttons do what they say. |
| `test_soak.gd` | 3 | Stress rounds: CPU "people" play every mode with chaos events switching far more often than normal, so many overlap and expire mid-action. Any engine error fails the test; every stat must be back to its unmodified baseline afterward (this is what proves the modifier stack can't leak a stuck buff/debuff). |

## Online multiplayer test (separate, takes longer)

```bash
godot --headless --path . -s tools/net_sync_test.gd
```

This runs a **real room server** and several **real headless client
processes** talking over actual localhost UDP (not simulated) — closer to
the real deployment than the unit tests above. Scenarios: normal sync (3
phones + 1 CPU buddy, Bounce Race), disconnect/reconnect with a seat held
open, mode coverage (Button Mayhem + Cake Dash), a cheating client sending
impossible moves (server must reject them), and two phones running the
actual Online lobby UI for two full rounds back-to-back. Rounds run in
real time (shortened to 30s each), so this takes a few minutes.

**Last run: 81 checks passed, 0 failed** (~5 minutes).

There's also a load-and-traffic test
(`godot --headless --path . -s tools/net_sync_test.gd -- --server-exe=...`
against an *exported* server binary) used to produce the CPU/RAM/bandwidth
numbers in [COST_AND_EFFORT_ESTIMATE.md](COST_AND_EFFORT_ESTIMATE.md).

## Manual / visual checks (not pass/fail — human judgment needed)

These render real frames under Xvfb and save screenshots; nothing
automatically grades them, a person has to look:

```bash
# Menu and basic gameplay
godot --path . --rendering-driver opengl3 --resolution 1280x720 -s tools/shot.gd -- --showcase --out=/tmp/showcase.png

# Every chaos event's announcement card and active-state look, in a real round
godot --path . --rendering-driver opengl3 --resolution 1280x720 -s tools/chaos_gallery.gd -- --mode=cake_dash --out-dir=/tmp/gallery

# Results screen in various finish states
godot --path . --rendering-driver opengl3 --resolution 1280x720 -s tools/results_gallery.gd -- --out-dir=/tmp/gallery

# Online lobby states
godot --path . --rendering-driver opengl3 --resolution 1280x720 -s tools/lobby_gallery.gd -- --out-dir=/tmp/gallery
```

Screenshots from the current build (menu + Cake Dash mid-round at two
camera distances) were reviewed during development and the camera framing
(`PartyCamera`) was tuned against them, but **no one has looked at this
game running on an actual phone screen or with a finger on actual glass.**
That's the single biggest gap between "tested" and "verified" here.

## Known limitations

Found by testing, not hidden from it:

1. **Bounce Race: CPU buddies can fall into the goo during the Bounce Mode
   chaos event**, specifically near the sliding platforms around
   `x≈0, z≈−58` to `z≈−71`. The Bounce Mode event makes platforms bouncy,
   which the current bot steering doesn't account for. Measured across 8
   seeds: 61 falls before any mitigation attempt, 27 falls after a partial
   mitigation — **still a known issue, not fixed.** Human players are not
   affected (only CPU buddy pathing); a human who falls just respawns at
   the last checkpoint, same as any other fall in that mode.
   (For comparison, the *Cake Dash* bot-pathing problem this same
   investigation started from — CPU buddies getting stuck or falling while
   walking to the cake — **was** fixed: a baked navigation mesh plus a
   hazard-timing hook that predicts the swinging hammer prop, bringing
   falls across 10 seeds from 165 down to 7. See the git history for that
   fix's commit.)
2. **No encryption on the online transport.** The room server uses raw
   ENet (UDP) with no DTLS/TLS. See
   [ONLINE_MULTIPLAYER_PLAN.md](ONLINE_MULTIPLAYER_PLAN.md) — this is
   flagged there as a release blocker for real-world use, not just a nice
   -to-have.
3. **No physical Android device has run this build.** Everything
   Android-specific beyond "the APK exports and is correctly signed and
   manifested" (see [ANDROID_BUILD.md](ANDROID_BUILD.md)) is unverified:
   real touch latency, real device performance, real screen notches/cutouts
   beyond the three aspect ratios `test_layout.gd` checks in a headless
   window.
4. **No play-testing with actual children in the target age range (9–12).**
   Difficulty balance, whether the humor lands, whether a 9-year-old can
   parse the HUD without help — all design intentions, none verified by
   watching a real kid play.
5. **Split-screen is not implemented** — all local players share one
   camera that frames everyone (see `PartyCamera`), not separate
   viewports. This was a design choice (party games built this way tend to
   stay more social — everyone looking at one screen together — and it
   avoids the complexity/performance cost of multiple 3D viewports on a
   phone), not an oversight, but it means a player who wanders far from
   the group can be framed small or temporarily off the camera's priority
   list.
6. **Accessibility beyond the above has not been reviewed** — no
   colorblind-safe palette audit, no screen-reader/TalkBack pass, no
   configurable text size. The HUD font (Fredoka) and high-contrast toy
   colors were a baseline design choice, not a tested accessibility
   feature.
7. **The room server logs connecting IP addresses** as part of ENet's
   normal connection handling — this is disclosed as a privacy
   consideration in [ONLINE_MULTIPLAYER_PLAN.md](ONLINE_MULTIPLAYER_PLAN.md)
   rather than hidden, but it hasn't been scrubbed or rotated/expired, which
   a real deployment serving children should do.
8. **No automated accessibility, performance-profiling, or memory-leak
   long-session test exists** beyond the soak test's "nothing throws an
   engine error and stats return to baseline" check. A multi-hour idle-app
   or repeated-scene-reload memory check hasn't been run.

## If you're picking this up next

The fastest way to find out if something changed/broke:
```bash
godot --headless --path . -s tools/check_project.gd          # ~seconds
godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn   # ~1 minute
godot --headless --path . -s tools/net_sync_test.gd           # ~5 minutes, online only
```
If all three are clean, the gaps above (real device, real kids, Bounce
Race bot pathing, transport encryption) are where to spend time next —
see [COST_AND_EFFORT_ESTIMATE.md](COST_AND_EFFORT_ESTIMATE.md) for a sizing
of each.
