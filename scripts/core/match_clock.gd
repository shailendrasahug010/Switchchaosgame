class_name MatchClock
extends RefCounted
## Shared round time that drives every moving obstacle.
##
## Moving platforms, spinners and swingers compute their position from the
## round clock instead of adding up their own deltas. Locally the match
## advances it every physics tick (so pausing freezes everything); online the
## network layer sets it from the server clock so all phones show obstacles in
## the same place.
##
## Always read it with [method now] (passing the asking node). The online room
## server runs several rounds at once, each inside its own SubViewport, and
## then every round keeps its own clock on that viewport.

const VIEWPORT_META := &"match_clock"

static var time: float = 0.0
## Online clients set this so time follows the server instead of local ticks.
static var externally_driven: bool = false
## True on the room server: clocks live on each room's viewport.
static var per_viewport: bool = false


static func reset(start_time: float = 0.0) -> void:
	time = start_time


static func advance(delta: float) -> void:
	if not externally_driven:
		time += delta


## Round time as seen by [param node].
static func now(node: Node = null) -> float:
	if per_viewport and node != null and node.is_inside_tree():
		var vp := node.get_viewport()
		if vp != null and vp.has_meta(VIEWPORT_META):
			return float(vp.get_meta(VIEWPORT_META))
	return time
