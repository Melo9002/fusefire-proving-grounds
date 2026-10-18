class_name ModularIndustrialLayoutBuilder
extends RefCounted

const SOURCE_KIND := "generated_modular_industrial"
const PRESETS: Array[StringName] = [&"industrial_frontage", &"loading_yard", &"road_and_shops", &"vertical_works"]

static func apply(data: MapData, cell_size: float, map_seed: int, preset: StringName = &"industrial_frontage") -> EnvironmentModuleLayout:
	var catalog := IndustrialModuleCatalog.create()
	var layout := EnvironmentModuleLayout.new(preset, map_seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed ^ 0x2202
	var placements := _placements_for(preset, rng)
	if placements.is_empty():
		layout.errors.append("Unknown modular environment preset: %s" % preset)
		return layout
	for placement in placements:
		if not layout.try_add(catalog[placement.component_id], placement, data.map_size):
			return layout
	if not _validate_layout(layout, catalog, data):
		return layout
	_apply_tactical_cells(data, layout, catalog, cell_size)
	data.source_kind = SOURCE_KIND if preset == &"industrial_frontage" else "%s_%s" % [SOURCE_KIND, preset]
	data.environment_modules.assign(layout.placements)
	data.environment_module_seed = map_seed
	data.rebuild_los_index()
	return layout

static func _placements_for(preset: StringName, rng: RandomNumberGenerator) -> Array[EnvironmentModulePlacement]:
	match preset:
		&"industrial_frontage": return _industrial_frontage(rng)
		&"loading_yard": return _loading_yard(rng)
		&"road_and_shops": return _road_and_shops()
		&"vertical_works": return _vertical_works()
		_: return []

static func _industrial_frontage(rng: RandomNumberGenerator) -> Array[EnvironmentModulePlacement]:
	return [
		EnvironmentModulePlacement.new(&"road_straight", Vector2i(1, 20)),
		EnvironmentModulePlacement.new(&"paving_square", Vector2i(11, 20)),
		EnvironmentModulePlacement.new(&"factory_interior_floor", Vector2i(11, 12)),
		EnvironmentModulePlacement.new(&"factory_wall_straight", Vector2i(11, 20)),
		EnvironmentModulePlacement.new(&"factory_doorway_wide", Vector2i(15, 20)),
		EnvironmentModulePlacement.new(&"factory_wall_straight", Vector2i(19, 20)),
		EnvironmentModulePlacement.new(&"factory_wall_corner", Vector2i(23, 19)),
		EnvironmentModulePlacement.new(&"factory_wall_straight", Vector2i(24, 15), 1),
		# Occupants intentionally share cells with the paving ground layer.
		EnvironmentModulePlacement.new(&"cargo_container", Vector2i(18, 23), 0, rng.randi_range(0, 2)),
		EnvironmentModulePlacement.new(&"cargo_container", Vector2i(30, 18), 1, rng.randi_range(0, 2)),
		EnvironmentModulePlacement.new(&"construction_barrier_vault", Vector2i(13, 23)),
	]

static func _loading_yard(rng: RandomNumberGenerator) -> Array[EnvironmentModulePlacement]:
	return [
		EnvironmentModulePlacement.new(&"industrial_loading_dock", Vector2i(8, 4)),
		EnvironmentModulePlacement.new(&"road_straight", Vector2i(8, 10)),
		EnvironmentModulePlacement.new(&"paved_courtyard", Vector2i(18, 4)),
		EnvironmentModulePlacement.new(&"cargo_container", Vector2i(9, 5), 1, rng.randi_range(0, 2)),
		EnvironmentModulePlacement.new(&"cargo_container", Vector2i(23, 8), 1, rng.randi_range(0, 2)),
		EnvironmentModulePlacement.new(&"machine_cover_cluster", Vector2i(18, 4)),
		EnvironmentModulePlacement.new(&"construction_barrier_vault", Vector2i(11, 8)),
	]

static func _road_and_shops() -> Array[EnvironmentModulePlacement]:
	return [
		EnvironmentModulePlacement.new(&"road_crossroad", Vector2i(10, 10)),
		EnvironmentModulePlacement.new(&"road_straight", Vector2i(10, 0)),
		EnvironmentModulePlacement.new(&"road_straight", Vector2i(10, 20)),
		EnvironmentModulePlacement.new(&"road_straight", Vector2i(0, 10), 1),
		EnvironmentModulePlacement.new(&"road_straight", Vector2i(20, 10), 1),
		EnvironmentModulePlacement.new(&"paved_courtyard", Vector2i(0, 0)),
		EnvironmentModulePlacement.new(&"paved_alley", Vector2i(24, 0)),
		EnvironmentModulePlacement.new(&"factory_shop_front", Vector2i(20, 9)),
		EnvironmentModulePlacement.new(&"factory_window_wall", Vector2i(28, 9)),
	]

static func _vertical_works() -> Array[EnvironmentModulePlacement]:
	return [
		EnvironmentModulePlacement.new(&"paving_square", Vector2i(8, 8)),
		EnvironmentModulePlacement.new(&"catwalk_stairs", Vector2i(10, 10)),
		EnvironmentModulePlacement.new(&"maintenance_platform", Vector2i(10, 12)),
		EnvironmentModulePlacement.new(&"maintenance_walkway", Vector2i(14, 12)),
		EnvironmentModulePlacement.new(&"factory_machine", Vector2i(8, 14)),
		EnvironmentModulePlacement.new(&"service_ramp", Vector2i(20, 8)),
	]

static func _validate_layout(layout: EnvironmentModuleLayout, catalog: Dictionary, data: MapData) -> bool:
	if layout.layout_id == &"industrial_frontage" and not _validate_frontage_access(layout, catalog):
		return false
	if layout.layout_id == &"loading_yard":
		var dock := _find(layout, &"industrial_loading_dock")
		var road := _find(layout, &"road_straight")
		if dock == null or road == null or not layout.placements_connect(dock, road, catalog):
			layout.errors.append("Loading dock must connect to its service road.")
			return false
	if layout.layout_id == &"road_and_shops" and not _validate_road_network(layout, catalog):
		return false
	if layout.layout_id == &"vertical_works":
		var stairs := _find(layout, &"catwalk_stairs")
		var platform := _find(layout, &"maintenance_platform")
		if stairs == null or platform == null or stairs.origin + Vector2i(0, 2) != platform.origin:
			layout.errors.append("Stairs must terminate on the maintenance platform.")
			return false
	for placement in layout.placements:
		var definition: EnvironmentModuleDefinition = catalog[placement.component_id]
		for clearance in layout.world_clearance_cells(definition, placement):
			var cell := data.get_cell(Vector3i(clearance.x, placement.elevation, clearance.y))
			if cell == null:
				layout.errors.append("Required clearance leaves the map at %s" % clearance)
				return false
			if _module_blocks(layout, catalog, clearance):
				layout.errors.append("Required clearance is blocked at %s" % clearance)
				return false
	return true

static func _validate_frontage_access(layout: EnvironmentModuleLayout, catalog: Dictionary) -> bool:
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
	return true

static func _validate_road_network(layout: EnvironmentModuleLayout, catalog: Dictionary) -> bool:
	var intersection := _find(layout, &"road_crossroad")
	if intersection == null:
		layout.errors.append("Road network requires a crossroad.")
		return false
	var connected_roads := 0
	for placement in layout.placements:
		if placement.component_id == &"road_straight" and layout.placements_connect(intersection, placement, catalog):
			connected_roads += 1
	if connected_roads != 4:
		layout.errors.append("Crossroad requires four connected road approaches; found %d." % connected_roads)
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
			var cell := data.get_cell(Vector3i(placement.origin.x + rotated.x, placement.elevation, placement.origin.y + rotated.y))
			if cell == null:
				continue
			var effect: Dictionary = definition.cell_effects[local_cell]
			cell.cover_type = effect.get("cover_type", MapCellData.CoverType.NONE)
			cell.cover_height = float(effect.get("cover_height", 0.0)) * cell_size
			cell.walkable = effect.get("walkable", true)
			cell.can_stop = effect.get("can_stop", cell.walkable)
			cell.blocks_line_of_sight = effect.get("blocks_los", false)
			cell.movement_cost = maxi(1, int(effect.get("movement_cost", 1)))
		for local_cell in definition.elevated_surfaces:
			var surface: Dictionary = definition.elevated_surfaces[local_cell]
			var rotated := definition.rotate_cell(local_cell, placement.rotation)
			var elevation := placement.elevation + int(surface.elevation)
			var ground := data.get_cell(Vector3i(placement.origin.x + rotated.x, placement.elevation, placement.origin.y + rotated.y))
			if ground == null:
				continue
			var position := Vector3i(placement.origin.x + rotated.x, elevation, placement.origin.y + rotated.y)
			var elevated := MapCellData.new(position, ground.world_position + Vector3.UP * float(elevation - placement.elevation) * cell_size)
			elevated.walkable = surface.get("walkable", true)
			elevated.can_stop = surface.get("can_stop", true)
			elevated.cover_type = surface.get("cover_type", MapCellData.CoverType.NONE)
			elevated.cover_height = float(surface.get("cover_height", 0.0)) * cell_size
			elevated.blocks_line_of_sight = surface.get("blocks_los", false)
			elevated.movement_cost = maxi(1, int(surface.get("movement_cost", 1)))
			data.add_cell(elevated)
		for link in definition.vertical_links:
			var from_cell := _world_vertical_point(definition, placement, link.from)
			var to_cell := _world_vertical_point(definition, placement, link.to)
			data.add_traversal_link(TraversalLinkData.new(from_cell, to_cell, link.bidirectional))
			data.generated_traversals.append(GeneratedTraversalData.new(link.kind, from_cell, to_cell))

static func _world_vertical_point(definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement, local: Vector3i) -> Vector3i:
	var rotated := definition.rotate_cell(Vector2i(local.x, local.z), placement.rotation)
	return Vector3i(placement.origin.x + rotated.x, placement.elevation + local.y, placement.origin.y + rotated.y)

static func _find(layout: EnvironmentModuleLayout, id: StringName) -> EnvironmentModulePlacement:
	for placement in layout.placements:
		if placement.component_id == id:
			return placement
	return null
