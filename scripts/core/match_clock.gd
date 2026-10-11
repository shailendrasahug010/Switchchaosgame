class_name MatchClock
extends RefCounted
## Shared round time that drives every moving obstacle.
##
## Moving platforms, spinners and swingers compute their position from
## [member time] instead of adding up their own deltas. Locally the match
## advances it every physics tick (so pausing freezes everything); online the
## network layer sets it from the server clock so all phones show obstacles in
## the same place.

static var time: float = 0.0
## Online clients set this so time follows the server instead of local ticks.
static var externally_driven: bool = false


static func reset(start_time: float = 0.0) -> void:
	time = start_time


static func advance(delta: float) -> void:
	if not externally_driven:
		time += delta
