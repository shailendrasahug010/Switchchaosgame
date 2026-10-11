class_name Layers
extends RefCounted
## Physics layer bit values (names are also set in Project Settings > Layer Names).

const WORLD := 1      ## layer 1: floors, walls, platforms
const PLAYERS := 2    ## layer 2: player characters (they pass through each other)
const PROPS := 4      ## layer 3: rigid props such as a dropped cake or beach balls
const TRIGGERS := 8   ## layer 4: pickups, checkpoints, finish zones
