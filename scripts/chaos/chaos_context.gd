class_name ChaosContext
extends RefCounted
## What a chaos event is allowed to touch while it runs.
## Events change the shared [member rules]; they never reach into players directly.

var rules: ModifierStack = ModifierStack.new()
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## The match node (for custom events that need the players or the arena). May be null in tests.
var match_node: Node = null
