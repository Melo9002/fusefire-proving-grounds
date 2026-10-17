class_name ModularIndustrialLayoutBuilder
extends RefCounted

const SOURCE_KIND := "generated_modular_industrial"

static func apply(data: MapData, cell_size: float, map_seed: int) -> EnvironmentModuleLayout:
	var catalog := IndustrialModuleCatalog.create()
	var layout := EnvironmentModuleLayout.new(&"industrial_frontage", map_seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed ^ 0x2202
	var placements: Array[EnvironmentModulePlacement] = [
		EnvironmentModulePlacement.new(&"road_straight", Vector2i(1, 20)),
		EnvironmentModulePlacement.new(&"paving_square", Vector2i(11, 20)),
		EnvironmentModulePlacement.new(&"factory_interior_floor", Vector2i(11, 13)),
		EnvironmentModulePlacement.new(&"factory_wall_straight", Vector2i(11, 19)),
		EnvironmentModulePlacement.new(&"factory_doorway_wide", Vector2i(14, 19)),
		EnvironmentModulePlacement.new(&"factory_wall_straight", Vector2i(17, 19)),
		EnvironmentModulePlacement.new(&"factory_wall_corner", Vector2i(20, 18)),
		EnvironmentModulePlacement.new(&"factory_wall_straight", Vector2i(21, 15), 1),
		# Occupants intentionally share cells with the paving ground layer.
		EnvironmentModulePlacement.new(&"cargo_container", Vector2i(18, 23), 0, rng.randi_range(0, 2)),
		EnvironmentModulePlacement.new(&"cargo_container", Vector2i(30, 18), 1, rng.randi_range(0, 2)),
		EnvironmentModulePlacement.new(&"construction_barrier_vault", Vector2i(13, 23)),
	]
	for placement in placements:
		if not layout.try_add(catalog[placement.component_id], placement, data.map_size):
			return layout
	if not _validate_access(layout, catalog, data):
		return layout
	_apply_tactical_cells(data, layout, catalog, cell_size)
	data.source_kind = SOURCE_KIND
	data.environment_modules.assign(layout.placements)
	data.environment_module_seed = map_seed
	data.rebuild_los_index()
	return layout

static func _validate_access(layout: EnvironmentModuleLayout, catalog: Dictionary, data: MapData) -> bool:
	var doorway := _find(layout, &"factory_doorway_wide")
	var interior := _find(layout, &"factory_interior_floor")
	var paving := _find(layout, &"paving_square")
	var road := _find(layout, &"road_straight")
	if doorway == null or interior == null or paving == null or road == null:
		layout.errors.append("Industrial frontage requires a road, paving transition, doorway and interior floor.")
		return false
	if not layout.placements_connect(doorway, interior, catalog) or not layout.placements_connect(doorway, paving, catalog):
		layout.errors.append("Doorway access connectors do not reach both interior and paving.")
		return false
	if not layout.placements_connect(road, paving, catalog):
		layout.errors.append("Road edge does not connect to the paved frontage.")
		return false
	for placement in layout.placements:
		var definition: EnvironmentModuleDefinition = catalog[placement.component_id]
		for clearance in layout.world_clearance_cells(definition, placement):
			var cell := data.get_cell(Vector3i(clearance.x, 0, clearance.y))
			if cell == null:
				layout.errors.append("Required clearance leaves the map at %s" % clearance)
				return false
			if _module_blocks(layout, catalog, clearance):
				layout.errors.append("Required doorway clearance is blocked at %s" % clearance)
				return false
	return true

static func _module_blocks(layout: EnvironmentModuleLayout, catalog: Dictionary, world_cell: Vector2i) -> bool:
	for placement in layout.placements:
		var definition: EnvironmentModuleDefinition = catalog[placement.component_id]
		for local_cell in definition.cell_effects:
			if placement.origin + definition.rotate_cell(local_cell, placement.rotation) != world_cell:
				continue
			if not definition.cell_effects[local_cell].get("walkable", true):
				return true
	return false

static func _apply_tactical_cells(data: MapData, layout: EnvironmentModuleLayout, catalog: Dictionary, cell_size: float) -> void:
	for placement in layout.placements:
		var definition: EnvironmentModuleDefinition = catalog[placement.component_id]
		for local_cell in definition.cell_effects:
			var rotated := definition.rotate_cell(local_cell, placement.rotation)
			var cell := data.get_cell(Vector3i(placement.origin.x + rotated.x, 0, placement.origin.y + rotated.y))
			if cell == null:
				continue
			var effect: Dictionary = definition.cell_effects[local_cell]
			cell.cover_type = effect.get("cover_type", MapCellData.CoverType.NONE)
			cell.cover_height = float(effect.get("cover_height", 0.0)) * cell_size
			cell.walkable = effect.get("walkable", true)
			cell.can_stop = effect.get("can_stop", cell.walkable)
			cell.blocks_line_of_sight = effect.get("blocks_los", false)
			cell.movement_cost = maxi(1, int(effect.get("movement_cost", 1)))

static func _find(layout: EnvironmentModuleLayout, id: StringName) -> EnvironmentModulePlacement:
	for placement in layout.placements:
		if placement.component_id == id:
			return placement
	return null
