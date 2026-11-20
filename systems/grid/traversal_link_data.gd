class_name TraversalLinkData
extends RefCounted

var from_cell: Vector3i
var to_cell: Vector3i
var bidirectional: bool
## What the link physically is, when the authored scene says: UNSPECIFIED (a generic vertical connection), RAMP and STAIRS (ElevationPath.surface_kind), LADDER (the ladder
## contract metadata). Low-cover transit is not a link at all (it is a vault transit cell). Presentation metadata only: it never changes legality or cost.
const UNSPECIFIED := 0
const RAMP := 1
const STAIRS := 2
const LADDER := 3
var surface_kind := 0
## For stairs: how many treads one one-cell link spans (the tread layout the map data does not otherwise carry).
var treads_per_step := 0
## For a RAMP link whose surface ENDS at the cell boundary before `to_cell` (the authored ramps stop half a cell short of the deck they serve, leaving a step at the lip, so
## `to_cell`'s floor is reached by stepping up, not by continuing the slope). Presentation only.
var step_at_to := false

func _init(start: Vector3i, end: Vector3i, two_way: bool = true) -> void:
	from_cell = start
	to_cell = end
	bidirectional = two_way
