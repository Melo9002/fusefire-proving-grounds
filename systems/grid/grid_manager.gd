extends Node
class_name GridManager

@export var cell_size: float = 1.0
@export var elevation_step: float = 1.0
@export var map_floor: CSGBox3D
var map_data := MapData.new()
var occupancy_map: Dictionary = {}

signal unit_registered(unit: TacticalUnit, grid_pos: Vector3i)
signal unit_unregistered(unit: TacticalUnit, grid_pos: Vector3i)

func register_unit(unit: TacticalUnit, grid_pos: Vector3i) -> void:
	occupancy_map[grid_pos] = unit
	unit.grid_position = grid_pos
	if unit.visual_adapter:
		unit.visual_adapter.presentation_grid = self
	print_rich("[color=cyan][GridManager][/color] Registered unit [b]%s[/b] at %s | Faction: %s" % [unit.name, grid_pos, unit.faction])
	unit_registered.emit(unit, grid_pos)

func unregister_unit_at(grid_pos: Vector3i) -> void:
	if occupancy_map.has(grid_pos):
		var unit = occupancy_map[grid_pos]
		occupancy_map.erase(grid_pos)
		unit_unregistered.emit(unit, grid_pos)

## Reserve the destination before animation; occupancy never changes terrain.
func update_unit_position(unit: TacticalUnit, from_grid: Vector3i, to_grid: Vector3i) -> void:
	if occupancy_map.get(from_grid) == unit:
		occupancy_map.erase(from_grid)
	occupancy_map[to_grid] = unit
	unit.grid_position = to_grid

func get_unit_grid(unit: TacticalUnit) -> Vector3i:
	return unit.grid_position

func is_cell_occupied(grid_pos: Vector3i) -> bool:
	return occupancy_map.has(grid_pos)

func get_unit_at(grid_pos: Vector3i) -> TacticalUnit:
	return occupancy_map.get(grid_pos, null)

func get_cell_data(grid_pos: Vector3i) -> MapCellData:
	return map_data.get_cell(grid_pos)

func can_unit_occupy_cell(_moving_unit: TacticalUnit, grid_pos: Vector3i) -> bool:
	var cell = get_cell_data(grid_pos)
	return cell != null and cell.walkable and cell.can_stop and not is_cell_occupied(grid_pos)

func grid_to_world(grid_pos: Vector3i) -> Vector3:
	if not map_floor:
		return Vector3.ZERO
	var half_width = map_floor.size.x / 2.0
	var half_depth = map_floor.size.z / 2.0
	var half_cell = cell_size / 2.0
	var floor_top_y = map_floor.global_position.y + (map_floor.size.y / 2.0)

	var world_x = (float(grid_pos.x) * cell_size) - half_width + half_cell
	var world_z = (float(grid_pos.z) * cell_size) - half_depth + half_cell
	return Vector3(world_x, floor_top_y + float(grid_pos.y) * elevation_step, world_z)

func world_to_grid(pos: Vector3) -> Vector3i:
	if not map_floor:
		return Vector3i.ZERO
	var half_width = map_floor.size.x / 2.0
	var half_depth = map_floor.size.z / 2.0
	var x = floori((pos.x + half_width) / cell_size)
	var z = floori((pos.z + half_depth) / cell_size)
	var column = map_data.get_column_cells(x, z)
	# A hill slope belongs to its surface cell even near the low edge of a tile.
	for hill in map_data.hills:
		if hill.footprint.has_point(Vector2i(x, z)):
			for surface: MapCellData in column:
				if surface.walkable:
					return surface.grid_position
	if column.is_empty():
		var floor_top_y = map_floor.global_position.y + (map_floor.size.y / 2.0)
		return Vector3i(x, roundi((pos.y - floor_top_y) / elevation_step), z)
	var nearest: MapCellData = column[0]
	for cell: MapCellData in column:
		if absf(cell.world_position.y - pos.y) < absf(nearest.world_position.y - pos.y):
			nearest = cell
	return nearest.grid_position

func get_tile_center(world_pos: Vector3) -> Vector3:
	return grid_to_world(world_to_grid(world_pos))
