class_name ModularIndustrialLayoutBuilder
extends RefCounted

const SOURCE_KIND := "generated_modular_industrial"
const PRESETS: Array[StringName] = [&"industrial_frontage", &"loading_yard", &"road_and_shops", &"vertical_works", &"building_gallery", &"asset_first_frontage", &"certified_equipment_parcel"]

# Task 2.3's bounded certification slice. These cells form one explicit access
# route from the imported road's inner sidewalk lane, across the imported
# paving forecourt, to the sealed shell's protected frontage apron.
const REFERENCE_ROAD_ACCESS := Vector2i(12, 14)
const REFERENCE_FRONTAGE_ACCESS := Vector2i(23, 14)

static func apply(data: MapData, cell_size: float, map_seed: int, preset: StringName = &"industrial_frontage", context: EnvironmentResolutionContext = null) -> EnvironmentModuleLayout:
	if context == null: context = EnvironmentResolutionContext.new()
	var catalog := context.catalog
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
	var resolved := context.resolve_layout(layout)
	for failure in context.errors: layout.errors.append("%s: %s" % [failure.code, failure.message])
	if not layout.errors.is_empty(): return layout
	for failure in EnvironmentModuleMapWriter.apply(data, layout, catalog, cell_size):
		layout.errors.append(failure.message)
	if not layout.errors.is_empty(): return layout
	data.source_kind = SOURCE_KIND if preset == &"industrial_frontage" else "%s_%s" % [SOURCE_KIND, preset]
	data.resolved_environment_modules = resolved
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
		&"building_gallery": return _building_gallery()
		&"asset_first_frontage": return _asset_first_frontage()
		&"certified_equipment_parcel": return _certified_equipment_parcel()
		_: return []

static func _certified_equipment_parcel() -> Array[EnvironmentModulePlacement]:
	var result: Array[EnvironmentModulePlacement] = [EnvironmentModulePlacement.new(&"road_straight", Vector2i(0, 10))]
	result.append_array(IndustrialEquipmentParcelDefinition.new().placements(Vector2i(10, 10)))
	return result

static func _asset_first_frontage() -> Array[EnvironmentModulePlacement]:
	return [
		# Two reviewed City Roads segments own the complete visible street section,
		# including their sidewalks and curbs.
		EnvironmentModulePlacement.new(&"road_straight", Vector2i(4, 5)),
		EnvironmentModulePlacement.new(&"road_straight", Vector2i(4, 15)),
		# Tile-low supplies an imported, flush pedestrian forecourt between the
		# street edge and the building apron; no procedural sidewalk is layered in.
		EnvironmentModulePlacement.new(&"paving_square", Vector2i(14, 5)),
		EnvironmentModulePlacement.new(&"paving_square", Vector2i(14, 15)),
		# building-i is a reviewed complete exterior shell. Quarter-turn 1 points
		# its normalized +Z frontage west toward the road while keeping it sealed.
		EnvironmentModulePlacement.new(&"industrial_shell_i", Vector2i(24, 10), 1),
		# The model-local -Z lamp head points toward the carriageway. Both fixtures
		# stay outside the central frontage band and the inner pedestrian lane.
		EnvironmentModulePlacement.new(&"street_light", Vector2i(13, 7), 3, 0),
		EnvironmentModulePlacement.new(&"street_light", Vector2i(13, 22), 3, 1),
	]

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
		EnvironmentModulePlacement.new(&"cargo_container", Vector2i(25, 8), 0, rng.randi_range(0, 2)),
		# Keep the measured overhang out of the neighboring cargo service clearance.
		EnvironmentModulePlacement.new(&"machine_cover_cluster", Vector2i(17, 4)),
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
		# The 2.7-cell machine envelope must not cut through the level-two platform.
		EnvironmentModulePlacement.new(&"factory_machine", Vector2i(7, 14)),
		EnvironmentModulePlacement.new(&"service_ramp", Vector2i(20, 8)),
	]

static func _building_gallery() -> Array[EnvironmentModulePlacement]:
	return [
		# Keep the gallery clear of FlatMapGenerator's edge deployment zones so
		# it remains a valid playable inspection map rather than a visual-only set.
		EnvironmentModulePlacement.new(&"industrial_building_shell", Vector2i(13, 1), 0, 0),
		EnvironmentModulePlacement.new(&"paved_courtyard", Vector2i(13, 18)),
		EnvironmentModulePlacement.new(&"complete_service_building", Vector2i(13, 18)),
		EnvironmentModulePlacement.new(&"paved_courtyard", Vector2i(27, 18)),
		EnvironmentModulePlacement.new(&"industrial_loading_canopy", Vector2i(28, 20)),
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
	if layout.layout_id == &"asset_first_frontage" and not _validate_asset_first_frontage(layout, catalog, data):
		return false
	if layout.layout_id == &"certified_equipment_parcel":
		var parcel := IndustrialEquipmentParcelDefinition.new()
		for error in parcel.validate(): layout.errors.append(error)
		var road := _find(layout, &"road_straight")
		var paving := _find(layout, &"paved_courtyard")
		if road == null or paving == null or not layout.placements_connect(road, paving, catalog):
			layout.errors.append("Certified equipment parcel must connect its paving service edge to the road sidewalk.")
		if not layout.errors.is_empty(): return false
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

static func _validate_asset_first_frontage(layout: EnvironmentModuleLayout, catalog: Dictionary, data: MapData) -> bool:
	var roads := _find_all(layout, &"road_straight")
	var paving := _find_all(layout, &"paving_square")
	var lights := _find_all(layout, &"street_light")
	var building := _find(layout, &"industrial_shell_i")
	if roads.size() != 2 or paving.size() != 2 or lights.size() != 2 or building == null:
		layout.errors.append("Asset-first frontage requires two roads, two paving tiles, two streetlights and building-i.")
		return false
	if not layout.placements_connect(roads[0], roads[1], catalog):
		layout.errors.append("Reference street segments must connect end-to-end.")
		return false
	for index in 2:
		if not layout.placements_connect(roads[index], paving[index], catalog):
			layout.errors.append("Reference sidewalk must meet its imported paving forecourt at segment %d." % index)
			return false
	var shell: EnvironmentModuleDefinition = catalog[building.component_id]
	if shell.rotate_direction(Vector2i.DOWN, building.rotation) != Vector2i.LEFT:
		layout.errors.append("Reference building frontage must face west toward the street.")
		return false
	for x in range(REFERENCE_ROAD_ACCESS.x, REFERENCE_FRONTAGE_ACCESS.x + 1):
		var cell := data.get_cell(Vector3i(x, 0, REFERENCE_ROAD_ACCESS.y))
		if cell == null or not cell.walkable or not cell.can_stop or _module_blocks(layout, catalog, Vector2i(x, REFERENCE_ROAD_ACCESS.y)):
			layout.errors.append("Reference frontage access is obstructed at (%d, %d)." % [x, REFERENCE_ROAD_ACCESS.y])
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

static func _find(layout: EnvironmentModuleLayout, id: StringName) -> EnvironmentModulePlacement:
	for placement in layout.placements:
		if placement.component_id == id:
			return placement
	return null

static func _find_all(layout: EnvironmentModuleLayout, id: StringName) -> Array[EnvironmentModulePlacement]:
	var result: Array[EnvironmentModulePlacement] = []
	for placement in layout.placements:
		if placement.component_id == id:
			result.append(placement)
	return result
