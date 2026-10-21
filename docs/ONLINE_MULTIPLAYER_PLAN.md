# Online multiplayer: what's built, what it costs, what's missing

The brief asked for "a documented path to private-room online multiplayer,"
not a finished live service. This is that: a working proof of concept,
tested with real separate processes talking over a real network, plus an
honest account of the gap between that and something you'd actually point
children at over the public internet.

## What exists today

**Architecture**: a dedicated, server-authoritative room server
(`scripts/net/net.gd`, `net_room.gd`, `net_protocol.gd`), built on Godot's
`ENetMultiplayerPeer` (UDP). One server process can host many rooms at
once (each room is one match, up to 4 seats). The same codebase runs the
server (headless, `--server`) and the game the players actually play — no
separate client build.

**How a group actually plays together right now**: there is no bundled,
always-on public server and no matchmaking. A grown-up runs the server
binary somewhere reachable (their own PC, a home server, a rented VPS —
see costs below) and enters that address once in a gated "Grown-ups" menu.
Players then pick **Make a Room** (gets a 5-character code, shown to
share out loud or by text — e.g. with the people already in the room, not
broadcast anywhere) or **Join a Room** (type the code). That's the whole
flow: no chat, no friends list, no typed names — players show up to each
other as "P1"–"P4" with their chosen creature, nothing else. This was a
deliberate child-safety choice, not a missing feature.

**Server authority**: the server runs the actual match simulation (chaos
events, scoring, win conditions) and treats client input as just that —
input, not fact. Each phone's position updates are sanity-checked against
how far a creature could plausibly have moved since its last update
(`net_room.gd`'s `max_h`/`max_v` check, generous enough to allow bounce
pads and knockback, strict enough to reject teleporting); a violation
snaps the client back to its last-known-good position server-side rather
than trusting what it sent. This was exercised by an automated "cheating
client" test (see below) that deliberately sends impossible moves and
checks the server rejects them.

**Sync cadence**: position updates at 20 Hz, mode-specific state (cake
carried, buttons lit, etc.) at 10 Hz, with 0.1s of client-side
interpolation to smooth the gaps between updates — standard, modest
numbers for a game this size, not tuned against real internet jitter (see
Gaps, below).

**Reconnect**: each seat gets a private rejoin token (a 128-bit random
value, not guessable) when a phone connects. If a phone drops, its seat is
held for 60 seconds — the match keeps running with a CPU buddy standing
in — and the same phone reconnecting with its token gets the seat back
mid-match. Tested automatically (see below).

**Room codes**: 5 characters from a 25-character alphabet with vowels and
easily-confused characters (I/1/L, O/0, S/5, etc.) removed, so a code read
aloud or texted is less likely to get mistyped. Generated with Godot's
`Crypto` class (a real CSPRNG), not a predictable counter.

**What's been tested, and how**: `tools/net_sync_test.gd` runs one real
server process and several real separate client processes over actual
localhost UDP (not simulated/mocked). Last run: **81 checks passed, 0
failed**, covering: normal sync (3 phones + 1 CPU buddy agreeing on phase,
timer, chaos events, positions, scores, and award outcomes), disconnect +
seat-held + reconnect, both Cake Dash and Button Mayhem under the same
protocol, a scripted cheating client, and two phones running the actual
Online lobby screens (not a test harness bypassing the UI) through two
full rounds. See [TESTING.md](TESTING.md) for the full breakdown.

**Load, measured on this development machine** (2 vCPU container, exported
Linux server binary, Cake Dash, real client processes, not simulated):

| Rooms (4 players each) | Server CPU | Server RSS |
|---|---|---|
| 1 room (4 players) | ~8% of 2 vCPUs | ~160 MB |
| 3 rooms (12 players) | ~21% mean of 2 vCPUs | ~185 MB |

**Bandwidth, measured from the server's own traffic logging**
(`--traffic-log=N`, logs every N seconds from `ENetConnection`'s real
packet counters — not estimated): roughly **5–8 KB/s sent and ~1–2.5 KB/s
received, per connected phone**, varying with how much is moving on
screen. For 4 players that's on the order of 25–35 KB/s sent total per
room, plus received — call it **~100–120 MB per hour for one full room of
4**, as a rough planning number (see the cost estimate doc for what that
means for a monthly bill).

## The gap: what this is not yet safe or ready to ship as

**No transport encryption — this is the release blocker.** The server uses
raw ENet over UDP with no DTLS/TLS layer. Today, anyone on the same
network path (a shared Wi-Fi, an ISP, anyone positioned to observe the
traffic) can read the room code, player inputs, and chaos-event state in
plaintext, and in principle inject packets, though the server-side
movement/state checks above limit what a forged packet could actually
*do* (it can't grant points or move a creature further than physically
plausible). This is acceptable for the same-network or VPN-style testing
this was built and tested under; it is **not** acceptable for an app aimed
at children to use over the open internet. Before any real deployment:
either move to `ENetMultiplayerPeer`'s DTLS support (Godot exposes this,
but it needs certificates and wasn't configured or tested here) or move
the transport to WebRTC/WebSocket-over-TLS instead (see alternatives,
below).

**No rate limiting beyond the movement-plausibility check** — a malicious
client could still flood the server with connection attempts or malformed
packets faster than the protocol expects. The `strikes` counter in
`net_room.gd` tracks repeated violations but nothing currently disconnects
a repeat offender; it's logged, not enforced.

**No abuse/moderation path** — there's no report button, no block, no way
for a kid to flag something, because there's also no open-ended
communication to abuse (no chat, no voice, no custom text anywhere in a
room). If a future version adds any player-to-player communication, this
whole safety model needs re-reviewing, not just extending.

**Privacy**: the server logs connecting IP addresses as a normal part of
ENet's connection handling, and the `--traffic-log` feature (used to
produce the numbers above) logs aggregate traffic stats, not message
content. Neither is currently scrubbed, rotated, or given a retention
limit — a real deployment serving children should set and document both
before launch, and this detail belongs in whatever privacy policy
accompanies a release.

**No server fleet/orchestration** — this is one server process handling
many rooms in-memory. It has no persistence (a server restart loses every
in-progress room — acceptable for 5-minute party-game rounds, but worth
stating), no horizontal scaling story, and no health-check/auto-restart
setup. One process comfortably handles a handful of rooms on a cheap VPS
(see the cost estimate for the measured numbers behind that); scaling past
roughly one CPU core's worth of rooms means running more server processes
side by side, not something this codebase does automatically today.

**Not load-tested past 3 concurrent rooms (12 players)** in this
environment — the trend (8% → 21% CPU mean going from 1 to 3 rooms on 2
vCPUs) is roughly linear, which is a reasonable basis for the capacity
estimates in the cost doc, but it's an extrapolation, not a measurement at
real scale.

## Alternatives considered, and why ENet was used here

| Approach | Trade-off |
|---|---|
| **ENet (used)** | Built into Godot, zero extra dependencies, low overhead, good for a LAN-party-style private room. Downside: no encryption without extra DTLS setup (the gap above), UDP can be blocked by some restrictive networks/firewalls. |
| **WebSocket (TLS)** | Works everywhere a browser does, encryption essentially free (wss://), easier to put behind standard web infrastructure (load balancers, etc.). Downside: TCP head-of-line blocking is a worse fit for real-time position updates than UDP; more moving parts to add to a GDScript-only project than ENet, which Godot already bundles. |
| **WebRTC (DataChannel)** | Encrypted by design (DTLS is mandatory in WebRTC), can do peer-to-peer without a relay for 2 players. Downside: meaningfully more complex to set up correctly (ICE/STUN/TURN for NAT traversal), and 3-4 player games usually end up needing a relay server anyway, which gives up the peer-to-peer benefit while keeping the complexity. |
| **A managed service (Nakama, PlayFab, Photon, etc.)** | Handles matchmaking, scaling, and often encryption for you; less custom code to maintain. Downside: an ongoing paid dependency, another vendor's data-handling practices to vet for a children's app (on top of your own), and it pulls scope away from "we control exactly what data this app sends and to whom," which matters more for a children's product than for most apps. |

For a private-room, invite-only, short-round party game, ENet plus a
proper DTLS setup (not full managed infrastructure) is the better fit —
but that DTLS setup is exactly the piece that's missing today.

## What shipping this for real would take

Roughly, in priority order:
1. **Add transport encryption** (DTLS over the existing ENet setup is the
   smallest change; see Godot's `ENetMultiplayerPeer` DTLS options).
   This is the one item that should block any release where players
   aren't all trusted/on one network.
2. **Decide on a hosting model** and write it down for parents: is a
   family expected to self-host (free, but needs a technically-inclined
   adult), or does the game's publisher run and pay for shared servers
   (see the cost estimate — modest for a small number of concurrent
   rooms, but it is an ongoing cost and an ongoing operational
   responsibility, including the privacy/retention commitments above)?
3. **Enforce the existing strike counter** (disconnect/ban a client that
   keeps sending invalid packets) rather than only logging it.
4. **Define and test a log retention/anonymization policy** for IPs and
   traffic stats before any deployment that isn't purely local testing.
5. **Load-test past 3 rooms** to confirm the near-linear CPU trend holds,
   and pick real capacity limits per server size from that, not an
   extrapolation.
6. Everything in [TESTING.md](TESTING.md)'s known-limitations list that
   touches online play (none currently do beyond what's listed above —
   the online-specific gaps are all here).

None of this has been started beyond what's described as "exists today."
