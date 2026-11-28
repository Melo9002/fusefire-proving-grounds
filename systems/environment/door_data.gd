class_name DoorData
extends RefCounted
## One authored door as the compiled map knows it: its identity and current state, the geometry it contributes in each supported state, and what changes in the map when it moves between them.
## Authoritative state: the live state is `state`; the map's cells, movement parts and shot obstacles always hold exactly that state's contribution (MapDoors applies a change atomically). The per-state data below is
## captured at compile time from the same compiler that builds the static maps (see MapDoors.capture), so a toggled map equals an independently compiled map of the other state.
const CLOSED := &"closed"
const OPEN := &"open"

var door_id: StringName
## The doorway cell (the cell the leaf stands in when closed).
var cell := Vector3i.ZERO
var state: StringName = CLOSED
var initial_state: StringName = CLOSED
## The leaf's hinge and swing, world units on the ground plane: the leaf sweeps the sector of `swing_radius` around `hinge` between the world directions `swing_from` (closed) and `swing_to` (open), radians as atan2(z, x).
var hinge := Vector2.ZERO
var swing_radius := 0.0
var swing_from := 0.0
var swing_to := 0.0
## State -> the leaf's movement-part boxes (world units).
var movement_parts: Dictionary = {}
## State -> {cell: field snapshot} for the cells that differ between the states (the complete affected region: the doorway, the cells beside the jambs, the cells the swung leaf covers or frees).
var cell_geometry: Dictionary = {}
## State -> the independently indexed shot obstacles the leaf's parts make in that state.
var shot_obstacles: Dictionary = {}


static func other(value: StringName) -> StringName:
	return OPEN if value == CLOSED else CLOSED


func record_part(part_state: StringName, bounds: AABB) -> void:
	if not movement_parts.has(part_state):
		movement_parts[part_state] = []
	movement_parts[part_state].append(bounds)


func region() -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for position: Vector3i in cell_geometry.get(state, {}).keys():
		cells.append(position)
	cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.x < b.x or (a.x == b.x and (a.y < b.y or (a.y == b.y and a.z < b.z))))
	return cells


func is_captured() -> bool:
	return cell_geometry.has(CLOSED) and cell_geometry.has(OPEN)


## A stable line for the replay fingerprint.
func fingerprint() -> String:
	return "door=%s,%d,%d,%d,%s" % [door_id, cell.x, cell.y, cell.z, state]
