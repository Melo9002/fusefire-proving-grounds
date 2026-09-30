extends UnitAction
class_name MoveAction

var unit: TacticalUnit
var target_tile: Vector3i
var path: PackedVector3Array
var grid_manager: GridManager
var ap_cost: int
var visual_segments: Array[StringName] = []

func _init(
	p_unit: TacticalUnit,
	p_target_tile: Vector3i,
	p_path: PackedVector3Array,
	p_grid_manager: GridManager,
	p_ap_cost: int = 1
) -> void:
	unit = p_unit
	target_tile = p_target_tile
	path = p_path
	grid_manager = p_grid_manager
	ap_cost = p_ap_cost

func is_valid() -> bool:
	if not is_instance_valid(unit) or not unit.stats or unit.stats.is_defeated or unit.is_moving:
		return false

	if not unit.stats.has_enough_ap(ap_cost):
		return false

	if path.is_empty():
		return false
	if not grid_manager or not grid_manager.can_unit_occupy_cell(unit, target_tile):
		return false

	return true

func execute() -> bool:
	if not is_valid():
		return false
	unit.stats.consume_ap(ap_cost)
	# Reserve the destination while the unit animates toward it.
	var current_grid = grid_manager.get_unit_grid(unit)
	grid_manager.update_unit_position(unit, current_grid, target_tile)
	unit.move_along_path(path, visual_segments)

	return true
