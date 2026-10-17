# Remaining work and operating cost estimate

Two different things, kept separate on purpose: **what it would cost to
run** the online servers (real measurements from this build, real current
prices), and **what work is left** before this is something you'd actually
ship (an estimate, not a measurement — treated as such throughout).

## Hosting cost, if you run private-room online play for real

The game needs **zero ongoing hosting cost** to play locally (one device,
2-4 players) or over a home network someone already has. A cost only
exists if you choose to run the online room server somewhere reachable
over the internet so players in different locations can use a room code
together.

### What was actually measured (this build, this sandbox, 2 vCPU container)

| Metric | Measured value |
|---|---|
| Server CPU, 1 room (4 players) | ~8% of 2 vCPUs |
| Server CPU, 3 rooms (12 players) | ~21% mean of 2 vCPUs |
| Server memory (RSS) | ~160–185 MB, 1–3 rooms |
| Traffic sent, per connected phone | ~5–8 KB/s |
| Traffic received, per connected phone | ~1–2.5 KB/s |

Source: `tools/net_sync_test.gd`'s load mode against the exported Linux
server binary, and the server's own `--traffic-log` output (reads real
packet counters from `ENetConnection`, not estimated). See
[ONLINE_MULTIPLAYER_PLAN.md](ONLINE_MULTIPLAYER_PLAN.md) for the test
methodology.

### Turning that into a monthly estimate

One important nuance: Godot's `SceneTree` runs one server process mostly
on a single core. The CPU measurements above (8% → 21% of a *2-vCPU*
container going from 1 to 3 rooms) suggest roughly **0.13–0.14 vCPU-worth
of load per active room of 4**, so a budget of "one full vCPU" is a
reasonable, slightly conservative capacity ceiling **per server process**
— call it **~7 rooms (≈28 players) actively playing at once** before you'd
want a second server process (on a second port) rather than assuming a
multi-core box lets one process scale linearly with core count.

Bandwidth per room of 4 (sent + received, both directions, server's view)
works out to roughly **110 MB/hour**. A small VPS's monthly traffic
allowance (500 GB–20 TB, see below) comfortably covers even constant,
heavy use at that rate — bandwidth is not the limiting factor for a game
this size; CPU and RAM are.

### What a VPS costs (snapshot, see date below — verify before relying on it)

| Provider & plan | Specs | Price | Rooms it comfortably covers |
|---|---|---|---|
| Hetzner CX23 | 2 vCPU, 4 GB RAM, 20 TB traffic | **€5.49/mo** (+€0.50/mo for an IPv4 address = €5.99/mo) | ~7 rooms / ~28 concurrent players (one server process using ~1 vCPU budget, as above) |
| DigitalOcean Basic (512 MB) | 1 vCPU, 512 MB RAM, 500 GB traffic | **$4.00/mo** | A handful of rooms — RAM is the tighter limit here, not CPU |
| DigitalOcean Basic (1 GB) | 1 vCPU, 1 GB RAM, 1 TB traffic | **$6.00/mo** | Similar room count to the above with more headroom |

**Prices as retrieved: early August 2026.** Cloud pricing changes; treat
these as "the right order of magnitude and the right shape of plan to
look for," not a live quote — check the provider's current pricing page
before committing to one.

**Bottom line**: for a family, a classroom, or a small friend group,
**one ~€5-6/month server** is realistically enough, and it's the kind of
cost a single interested adult could cover personally without needing a
business model. Scaling to hundreds of simultaneous rooms (a real public
launch) would mean either a bigger box or multiple server processes behind
simple port-based room assignment — not a rewrite, but not configured or
tested here either.

### Other recurring costs, if you go beyond self/family hosting

- **Google Play developer registration**: a one-time (not recurring)
  **US$25** fee, not monthly.
- **A domain name**, if you want `play.yourgame.com` instead of a raw IP
  for the server address field — typically $10-15/year, optional (the
  grown-up server-address field accepts a plain IP just fine).
- **No other paid services are used or required anywhere in this
  project** — no analytics SaaS, no crash-reporting SaaS, no ad network,
  no backend-as-a-service. Everything else (engine, font, generated audio)
  is free and already in the repo.

## Remaining work estimate

This is **a judgment call, not a measurement** — unlike the hosting
numbers above, there's no way to verify an effort estimate by running it.
Treat the day-ranges as what one capable GDScript developer, already
familiar with this codebase, would plausibly need — a professional studio
or a complete newcomer to the code would both shift these in opposite
directions, and the project owner knows their own situation (and the rate
or budget to attach to a day, if any) better than this estimate can.

| Item | Why it's not done | Rough effort |
|---|---|---|
| Fix Bounce Race CPU-buddy falls during Bounce Mode | Needs the same kind of hazard-timing work the Cake Dash fix used, adapted to moving/bouncy platforms instead of a swinging hammer | 1–3 days |
| Add transport encryption (DTLS) to online play | Not configured; needs certs and testing against the existing room-server flow | 2–4 days |
| Enforce the existing cheat "strikes" counter (disconnect repeat offenders) | Currently logged but not acted on | 0.5–1 day |
| Real Android device testing pass | Never run on physical hardware in this environment | 1–3 days, depends on how many devices/issues turn up |
| Release signing + a first real Play Console submission | Needs a release keystore, Gradle/AAB build (untested here — see [ANDROID_BUILD.md](ANDROID_BUILD.md)), Play's closed-testing period | 2–5 days of work, **plus a mandatory 14-day calendar wait** for the closed-testing requirement (not work time, just elapsed time) |
| Privacy policy + Play Data Safety form, written to match what the app actually does | Not written; this doc and the build guide give the actual facts (what data is collected, where IPs are logged) to write it from, but someone should still have it reviewed | 1–2 days to draft, plus legal review time outside this estimate |
| COPPA / Play Families / India DPDP compliance review | Explicitly flagged throughout as not legal advice and not done | Not estimated here — needs an actual lawyer or compliance specialist, whose timeline isn't something this estimate can guess |
| Play-testing with real kids in the target age range, and balance/difficulty pass from what's learned | No child playtesting has happened | 1–2 days to run sessions, variable follow-up depending on findings |
| Accessibility pass (colorblind check, text scaling, TalkBack) | Not reviewed at all beyond the toy-bright default palette | 2–4 days for a first pass |
| Basic CI (run the test suite + static check on every push) | Not set up — the commands in [TESTING.md](TESTING.md) are ready to drop into any CI runner that can run a headless Godot binary | 0.5–1 day |
| Load-test online play past 3 concurrent rooms to confirm the capacity numbers above | Only measured up to 3 rooms; the estimate above extrapolates | 0.5–1 day |

**Not included above** because they're genuine product decisions, not
fixed-scope engineering tasks: more arenas/modes, more chaos events, more
characters/cosmetics, music/SFX variety, a tutorial, or split-screen (a
deliberate design choice today, not a bug — see
[TESTING.md](TESTING.md)'s known limitations). Sizing those depends
entirely on how much of each the project owner wants.

## What this estimate is built on

Every number in the hosting section above traces to a command that was
actually run and a log that was actually read — see
[ONLINE_MULTIPLAYER_PLAN.md](ONLINE_MULTIPLAYER_PLAN.md) and
[TESTING.md](TESTING.md) for exactly which ones. The effort estimates are
explicitly the less certain half of this document and are labeled that way
on purpose.
