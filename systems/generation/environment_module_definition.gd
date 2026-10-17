class_name EnvironmentModuleDefinition
extends RefCounted

enum TacticalRole {
	GROUND,
	STRUCTURE,
	SOLID_OBSTACLE,
	VAULTABLE_OBSTACLE,
	VISUAL_ONLY,
}

enum CellInteraction {
	OPEN,
	BLOCKED,
	VAULT,
	WALK_OVER,
}

enum PlacementLayer {
	GROUND,
	OCCUPANT,
	OVERHEAD,
}

var component_id: StringName
var family: StringName
var size: Vector2i
var footprint_cells: Array[Vector2i] = []
var clearance_cells: Array[Vector2i] = []
var cell_effects: Dictionary = {}
var connections: Array[EnvironmentModuleConnection] = []
var visuals: Array[Dictionary] = []
var allowed_rotations: Array[int] = [0, 1, 2, 3]
var tactical_role: TacticalRole = TacticalRole.VISUAL_ONLY
## Components collide only with reservations on the same placement layer.
## This allows an obstacle to occupy cells that already have a ground surface.
var placement_layer: PlacementLayer = PlacementLayer.OCCUPANT
## Presentation authoring convention only. Tactical placement remains integer-cell based.
var visual_origin_snap := Vector2(0.5, 0.5)
var visual_assembly_pitch := Vector2.ZERO
var calibration_note := ""

func _init(id: StringName, component_family: StringName, dimensions: Vector2i) -> void:
	component_id = id
	family = component_family
	size = dimensions
	for x in dimensions.x:
		for z in dimensions.y:
			footprint_cells.append(Vector2i(x, z))

func rotated_size(rotation: int) -> Vector2i:
	return size if posmod(rotation, 2) == 0 else Vector2i(size.y, size.x)

func rotate_cell(cell: Vector2i, rotation: int) -> Vector2i:
	match posmod(rotation, 4):
		1: return Vector2i(size.y - 1 - cell.y, cell.x)
		2: return Vector2i(size.x - 1 - cell.x, size.y - 1 - cell.y)
		3: return Vector2i(cell.y, size.x - 1 - cell.x)
		_: return cell

func rotate_direction(direction: Vector2i, rotation: int) -> Vector2i:
	var result := direction
	for _step in posmod(rotation, 4):
		result = Vector2i(-result.y, result.x)
	return result

func rotated_cells(cells: Array[Vector2i], rotation: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in cells:
		result.append(rotate_cell(cell, rotation))
	return result

func add_connection(cell: Vector2i, direction: Vector2i, type: EnvironmentModuleConnection.Type) -> EnvironmentModuleDefinition:
	connections.append(EnvironmentModuleConnection.new(cell, direction, type))
	return self

func set_effect(cell: Vector2i, effect: Dictionary) -> EnvironmentModuleDefinition:
	cell_effects[cell] = effect.duplicate(true)
	return self

func set_tactical_role(role: TacticalRole) -> EnvironmentModuleDefinition:
	tactical_role = role
	return self

func set_placement_layer(layer: PlacementLayer) -> EnvironmentModuleDefinition:
	placement_layer = layer
	return self

func set_visual_convention(origin_snap: Vector2, assembly_pitch: Vector2, note := "") -> EnvironmentModuleDefinition:
	visual_origin_snap = origin_snap
	visual_assembly_pitch = assembly_pitch
	calibration_note = note
	return self

func interaction_at(cell: Vector2i) -> CellInteraction:
	var effect: Dictionary = cell_effects.get(cell, {})
	return effect.get("interaction", CellInteraction.OPEN)

func add_visual(asset_path: String, local_cell: Vector2, scale: float, yaw_quarters := 0, anchor := 0, offset := Vector3.ZERO) -> EnvironmentModuleDefinition:
	visuals.append({
		"asset_path": asset_path,
		"local_cell": local_cell,
		"scale": scale,
		"yaw_quarters": yaw_quarters,
		"anchor": anchor,
		"offset": offset,
	})
	return self
