class_name NetProtocol
extends RefCounted
## Shared constants and checks for online play (used by both the room server
## and the phones). See docs/ONLINE_MULTIPLAYER_PLAN.md for the whole design.
##
## Everything a phone sends is treated as untrusted: every value is checked
## here or in NetRoom before it can change anything.

## Bump when the messages change: older phones are asked to update.
const VERSION := 1
const DEFAULT_PORT := 7777
const MAX_SEATS := 4
const CODE_LENGTH := 5
## No vowels (so codes never spell words) and no look-alike characters
## (0/O, 1/I/L, 5/S, U/V, ...): easy to read out and type for kids.
const CODE_ALPHABET := "BCDFGHJKMNPQRTVWXZ2346789"

## How often phones send their creature, and the server sends snapshots.
const SEND_RATE := 20
## How often the mode's state rides along with a snapshot.
const MODE_STATE_RATE := 10
## Phones show other creatures this far in the past, so there are always two
## snapshots to blend between.
const INTERP_DELAY := 0.1
## A seat is kept this long for a player who lost the connection.
const RECONNECT_GRACE := 60.0
## The round starts when every phone has loaded the arena, or after this.
const LOAD_TIMEOUT := 15.0
## An empty room (nobody connected) closes after this.
const EMPTY_ROOM_TIMEOUT := 60.0
## A lobby nobody touches closes after this.
const IDLE_ROOM_TIMEOUT := 30.0 * 60.0

## Error codes the server sends (s_error) and what the phone shows for them.
const ERRORS := {
	"room_not_found": "We couldn't find that room. Check the code and try again!",
	"room_full": "That room is full (4 players). Ask for a new room!",
	"bad_code": "Room codes have 5 letters and numbers.",
	"too_many_tries": "Too many tries. Wait a moment, then try again.",
	"server_full": "The game server is very busy. Please try again later.",
	"update_needed": "This game needs an update to play online with this server.",
	"not_host": "Only the player who made the room can do that.",
	"cant_start": "The round can't start right now.",
	"rejoin_failed": "That room has closed. You can make a new one!",
	"connect_failed": "We couldn't reach the game server. Ask a grown-up to check the server address.",
	"lost_connection": "The connection to the room was lost.",
	"kicked": "You were removed from the room.",
}


static func error_text(code: String) -> String:
	return ERRORS.get(code, "Something went wrong. Please try again.")


## A fresh random room code (not guessable: uses the system's secure random).
static func make_code() -> String:
	var bytes := Crypto.new().generate_random_bytes(CODE_LENGTH * 2)
	var out := ""
	for i in CODE_LENGTH:
		var v := (bytes[i * 2] << 8) | bytes[i * 2 + 1]
		out += CODE_ALPHABET[v % CODE_ALPHABET.length()]
	return out


## A secret that lets a phone take its seat back after losing the connection.
static func make_token() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


## Uppercases, drops spaces and dashes. Does not check validity.
static func normalize_code(text: String) -> String:
	return text.strip_edges().to_upper().replace(" ", "").replace("-", "")


static func is_valid_code(code: String) -> bool:
	if code.length() != CODE_LENGTH:
		return false
	for c in code:
		if not CODE_ALPHABET.contains(c):
			return false
	return true


static func is_valid_token(token: String) -> bool:
	return token.length() == 32 and token.is_valid_hex_number(false)


## The look a phone asked for, checked against the catalog. Anything unknown
## falls back to a default. (Cosmetics never change how a creature plays.)
static func clean_look(look: Variant) -> Dictionary:
	var out := {"character": "bloop", "hat": "none", "paint": "classic"}
	if typeof(look) != TYPE_DICTIONARY:
		return out
	var c := String(look.get("character", "")) if look.get("character") is String else ""
	var h := String(look.get("hat", "")) if look.get("hat") is String else ""
	var p := String(look.get("paint", "")) if look.get("paint") is String else ""
	for ch in Catalog.CHARACTERS:
		if String(ch.id) == c:
			out.character = c
	for hat in Catalog.HATS:
		if String(hat.id) == h:
			out.hat = h
	for paint in Catalog.PAINTS:
		if String(paint.id) == p:
			out.paint = p
	return out


static func is_online_mode(mode_id: String) -> bool:
	for m in Catalog.MODES:
		if String(m.id) == mode_id:
			return bool(m.get("online", false))
	return false


## Server time in seconds (monotonic, since the program started).
static func now() -> float:
	return Time.get_ticks_usec() / 1000000.0


## Packs a creature for a snapshot or a phone update: 9 floats.
static func pack_player(p: PlayerCharacter) -> PackedFloat32Array:
	var flags := 0
	if p.grounded():
		flags |= 1
	if p.is_respawning:
		flags |= 2
	var pos := p.global_position
	var vel := p.velocity
	return PackedFloat32Array([pos.x, pos.y, pos.z, vel.x, vel.y, vel.z, p.facing_yaw(), p.size_scale, float(flags)])


const PLAYER_FLOATS := 9


## True when every number is a normal finite value.
static func all_finite(data: PackedFloat32Array) -> bool:
	for v in data:
		if is_nan(v) or is_inf(v):
			return false
	return true
