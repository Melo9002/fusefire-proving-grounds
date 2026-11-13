class_name MapCellData
extends RefCounted

enum CoverType {
	NONE,
	LOW,
	FULL,
}

var grid_position: Vector3i
var world_position: Vector3
var elevation: float = 0.0
var walkable: bool = true
var can_stop: bool = true
var cover_type: CoverType = CoverType.NONE
var cover_height: float = 0.0
var blocks_line_of_sight: bool = false
## Optional sub-cell obstruction from an explicit authored solid.
var authored_shot_bounds := AABB()
## Revision 3 retains distinct authored parts when their cell reservations overlap.
var authored_shot_parts: Array[AABB] = []
var movement_cost: int = 1
## Optional authored environmental exposure. Empty cells have no hazard.
var hazard_condition: ConditionDefinition

func _init(cell: Vector3i, position: Vector3) -> void:
	grid_position = cell
	world_position = position
	elevation = position.y
