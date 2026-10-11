class_name Catalog
extends RefCounted
## Static game content: characters, cosmetics, modes and chaos events.
## Everything here is data — add a hat or a character by adding a row.
## Cosmetics are earned through play only. There are no purchases and no
## random rewards; every unlock rule is visible to the player.

const CHARACTERS: Array[Dictionary] = [
	{
		"id": &"bloop", "name": "Bloop", "shape": &"ball",
		"color": Color(0.247, 0.616, 1.0), "accent": Color(1.0, 0.882, 0.302),
		"accessory": &"antenna", "voice_pitch": 1.0,
		"blurb": "A bouncy blue blob who thinks every floor is a trampoline.",
	},
	{
		"id": &"jelly", "name": "Jelly", "shape": &"bean",
		"color": Color(1.0, 0.435, 0.71), "accent": Color(1.0, 1.0, 1.0),
		"accessory": &"bunny_ears", "voice_pitch": 1.25,
		"blurb": "A tall jellybean with floppy ears and very fast feet.",
	},
	{
		"id": &"mossy", "name": "Mossy", "shape": &"gumdrop",
		"color": Color(0.31, 0.824, 0.478), "accent": Color(1.0, 0.69, 0.231),
		"accessory": &"sprout", "voice_pitch": 0.8,
		"blurb": "A chunky gumdrop with a sprout that wiggles when it's happy.",
	},
	{
		"id": &"sunny", "name": "Sunny", "shape": &"egg",
		"color": Color(1.0, 0.788, 0.235), "accent": Color(1.0, 0.373, 0.373),
		"accessory": &"propeller", "voice_pitch": 1.1,
		"blurb": "A sunny egg wearing a propeller cap. It does not fly. Yet.",
	},
]

## Hats sit on top of any character. "unlock" lists stat milestones (all must be met).
const HATS: Array[Dictionary] = [
	{"id": &"none", "name": "No Hat", "unlock": {}},
	{"id": &"party_hat", "name": "Party Hat", "unlock": {"rounds_played": 1}},
	{"id": &"bow", "name": "Big Bow", "unlock": {"stars": 5}},
	{"id": &"shades", "name": "Cool Shades", "unlock": {"rounds_played": 3}},
	{"id": &"chef_hat", "name": "Chef Hat", "unlock": {"cakes_delivered": 1}},
	{"id": &"flower", "name": "Flower Clip", "unlock": {"buttons_pressed": 10}},
	{"id": &"crown", "name": "Paper Crown", "unlock": {"races_finished": 3}},
	{"id": &"headphones", "name": "Comfy Headphones", "unlock": {"stars": 20}},
	{"id": &"top_hat", "name": "Tiny Top Hat", "unlock": {"rounds_played": 10}},
]

## Paint jobs recolor the body. "classic" keeps the character's own color.
const PAINTS: Array[Dictionary] = [
	{"id": &"classic", "name": "Classic", "unlock": {}},
	{"id": &"mint", "name": "Mint", "color": Color(0.49, 1.0, 0.816), "unlock": {"rounds_played": 2}},
	{"id": &"grape", "name": "Grape", "color": Color(0.655, 0.482, 1.0), "unlock": {"stars": 10}},
	{"id": &"sunset", "name": "Sunset", "color": Color(1.0, 0.541, 0.298), "unlock": {"party_points": 3000}},
	{"id": &"bubblegum", "name": "Bubblegum", "color": Color(1.0, 0.62, 0.86), "unlock": {"rounds_played": 6}},
	{"id": &"midnight", "name": "Midnight", "color": Color(0.33, 0.36, 0.78), "unlock": {"party_points": 8000}},
]

const MODES: Array[Dictionary] = [
	{
		"id": &"cake_dash", "name": "Cake Dash",
		"scene": "res://scenes/arenas/cake_dash.tscn",
		"blurb": "Carry the giant birthday cake to the party. Don't let it go SPLAT!",
		"color": Color(1.0, 0.56, 0.76), "team": true,
	},
	{
		"id": &"button_mayhem", "name": "Button Mayhem",
		"scene": "res://scenes/arenas/button_mayhem.tscn",
		"blurb": "Press the colored buttons in the right order. Some of them run away!",
		"color": Color(0.36, 0.74, 1.0), "team": true,
	},
	{
		"id": &"bounce_race", "name": "Bounce Race",
		"scene": "res://scenes/arenas/bounce_race.tscn",
		"blurb": "Boing over trampolines and spinners. First to the finish wins!",
		"color": Color(0.49, 0.88, 0.45), "team": false,
	},
]

const CHAOS_EVENTS: Array[String] = [
	"res://data/chaos_events/penguin.tres",
	"res://data/chaos_events/moon.tres",
	"res://data/chaos_events/slippery.tres",
	"res://data/chaos_events/giant.tres",
	"res://data/chaos_events/bounce.tres",
	"res://data/chaos_events/reverse.tres",
	"res://data/chaos_events/tiny.tres",
	"res://data/chaos_events/sticky.tres",
]

## Button Mayhem buttons. Every color also has its own symbol so the game can
## be played without telling colors apart.
const BUTTON_COLORS: Array[Dictionary] = [
	{"id": &"red", "name": "Red", "color": Color(1.0, 0.3, 0.43), "symbol": &"heart"},
	{"id": &"blue", "name": "Blue", "color": Color(0.247, 0.616, 1.0), "symbol": &"circle"},
	{"id": &"yellow", "name": "Yellow", "color": Color(1.0, 0.824, 0.247), "symbol": &"star"},
	{"id": &"green", "name": "Green", "color": Color(0.184, 0.788, 0.478), "symbol": &"triangle"},
	{"id": &"purple", "name": "Purple", "color": Color(0.655, 0.482, 1.0), "symbol": &"diamond"},
	{"id": &"orange", "name": "Orange", "color": Color(1.0, 0.541, 0.298), "symbol": &"square"},
]

## Colors that tell players apart in UI chips and name tags (P1..P4).
const PLAYER_TAG_COLORS: Array[Color] = [
	Color(0.247, 0.616, 1.0),
	Color(1.0, 0.435, 0.71),
	Color(0.31, 0.824, 0.478),
	Color(1.0, 0.788, 0.235),
]


static func character(id: StringName) -> Dictionary:
	for c in CHARACTERS:
		if c.id == id:
			return c
	return CHARACTERS[0]


static func character_index(id: StringName) -> int:
	for i in CHARACTERS.size():
		if CHARACTERS[i].id == id:
			return i
	return 0


static func hat(id: StringName) -> Dictionary:
	for h in HATS:
		if h.id == id:
			return h
	return HATS[0]


static func paint(id: StringName) -> Dictionary:
	for p in PAINTS:
		if p.id == id:
			return p
	return PAINTS[0]


static func button_color(id: StringName) -> Dictionary:
	for b in BUTTON_COLORS:
		if b.id == id:
			return b
	return BUTTON_COLORS[0]


static func mode(id: StringName) -> Dictionary:
	for m in MODES:
		if m.id == id:
			return m
	return MODES[0]


static func mode_index(id: StringName) -> int:
	for i in MODES.size():
		if MODES[i].id == id:
			return i
	return 0


## Body color for a character wearing a paint job.
static func body_color(character_id: StringName, paint_id: StringName) -> Color:
	var p := paint(paint_id)
	if p.has("color"):
		return p.color
	return character(character_id).color


static func load_chaos_library() -> Array[ChaosEvent]:
	var events: Array[ChaosEvent] = []
	for path in CHAOS_EVENTS:
		var ev := load(path) as ChaosEvent
		if ev == null:
			push_error("Catalog: could not load chaos event %s" % path)
			continue
		events.append(ev)
	return events


## Every cosmetic (hats + paints) as one list, used by unlock checks.
static func all_cosmetics() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(HATS)
	out.append_array(PAINTS)
	return out
