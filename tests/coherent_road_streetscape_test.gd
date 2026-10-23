extends SceneTree

const Streetscape = preload("res://systems/generation/road_streetscape_profile.gd")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_cross_section_contract()
	_test_environment_streetscapes()
	_test_presented_sections()
	print("Coherent road streetscapes: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_cross_section_contract() -> void:
	check(is_equal_approx(Streetscape.CARRIAGEWAY_WIDTH + Streetscape.SIDEWALK_WIDTH * 2.0, Streetscape.TILE_SIZE), "Carriageway and sidewalks exactly fill the ten-cell street pitch")
	var straight := Streetscape.surface_sections(&"road_straight")
	check(_section_count(straight, Streetscape.ASPHALT) == 1, "Straight streets use one continuous carriageway strip")
	check(_section_count(straight, Streetscape.SIDEWALK) == 2, "Straight streets provide a sidewalk on each side")
	check(_section_count(straight, Streetscape.CURB) == 2, "Straight streets provide a curb on each carriageway edge")
	check(Streetscape.sidewalk_cells(&"road_straight").size() == 40, "Straight streets reserve two walkable sidewalk cells on both sides")
	for intersection_id in [&"road_crossroad", &"road_intersection_t"]:
		var sections := Streetscape.surface_sections(intersection_id)
		check(not sections.is_empty() and _section_count(sections, Streetscape.ASPHALT) >= 2, "%s authors connected intersection pavement" % intersection_id)
		check(_section_count(sections, Streetscape.SIDEWALK) >= 3, "%s preserves pedestrian corner islands" % intersection_id)

func _test_environment_streetscapes() -> void:
	var catalog := IndustrialModuleCatalog.create()
	for environment_id in CoherentEnvironmentAssembler.ENVIRONMENTS:
		for map_seed in [17, 2208, 7319]:
			var data := FlatMapGenerator.generate_coherent_environment(50, 40, 1.0, map_seed, environment_id)
			var roads: Array[EnvironmentModulePlacement] = []
			var placement_lookup: Dictionary = {}
			for placement in data.environment_modules:
				placement_lookup["%s@%s" % [placement.component_id, placement.origin]] = placement
				var definition: EnvironmentModuleDefinition = catalog[placement.component_id]
				if definition.module_type in [EnvironmentModuleDefinition.ModuleType.ROAD, EnvironmentModuleDefinition.ModuleType.INTERSECTION]:
					roads.append(placement)
			var straight_index := 0
			for road in roads:
				var definition: EnvironmentModuleDefinition = catalog[road.component_id]
				if definition.module_type == EnvironmentModuleDefinition.ModuleType.INTERSECTION:
					_check_intersection_fixtures(environment_id, road, definition, placement_lookup)
				else:
					_check_straight_fixtures(environment_id, straight_index, road, definition, placement_lookup, data.environment_layout_plan)
					_check_clear_sidewalk_path(data, road, definition)
					straight_index += 1
			check(_road_cells_preserve_tactical_authority(data, roads, catalog), "%s seed %d keeps streets tactically open except explicit barriers" % [environment_id, map_seed])
			check(_has_streetscape_diagnostic(data.environment_layout_plan.decisions), "%s seed %d records streetscape placement diagnostics" % [environment_id, map_seed])

func _check_intersection_fixtures(environment_id: StringName, road: EnvironmentModulePlacement, definition: EnvironmentModuleDefinition, lookup: Dictionary) -> void:
	var fixture_id := CoherentEnvironmentAssembler._intersection_fixture_id(environment_id, road.component_id)
	var seen: Dictionary = {}
	for connection in definition.connections:
		if connection.type != EnvironmentModuleConnection.Type.ROAD or seen.has(connection.direction):
			continue
		seen[connection.direction] = true
		var fixture := Streetscape.approach_fixture(connection.direction)
		var world_cell := road.origin + definition.rotate_cell(fixture.cell, road.rotation)
		check(lookup.has("%s@%s" % [fixture_id, world_cell]), "%s places a reviewed %s kit asset at every active intersection approach" % [environment_id, fixture_id])

func _check_straight_fixtures(environment_id: StringName, index: int, road: EnvironmentModulePlacement, definition: EnvironmentModuleDefinition, lookup: Dictionary, plan: EnvironmentLayoutPlan) -> void:
	var fixture := Streetscape.straight_fixture_slot(index)
	var fixture_id := CoherentEnvironmentAssembler._straight_fixture_id(environment_id, index)
	var fixture_cell := road.origin + definition.rotate_cell(fixture.cell, road.rotation)
	var placement_key := "%s@%s" % [fixture_id, fixture_cell]
	var placed := lookup.has(placement_key)
	var skipped_prefix := "streetscape skipped %s@%d,0,%d:" % [fixture_id, fixture_cell.x, fixture_cell.y]
	var skipped_explicitly := plan.decisions.any(func(decision):
		return decision.begins_with(skipped_prefix)
	)
	check(placed or skipped_explicitly, "%s either places its reviewed %s kit asset or records its optional rejection at the authored slot" % [environment_id, fixture_id])
	if fixture_id == &"street_light" and placed:
		var light: EnvironmentModulePlacement = lookup["%s@%s" % [fixture_id, fixture_cell]]
		check(light.rotation == posmod(int(fixture.inward_yaw) + road.rotation, 4), "Streetlight model-local -Z faces inward toward the carriageway")
	if CoherentEnvironmentAssembler._should_add_street_obstacle(environment_id, index):
		var obstacle := Streetscape.straight_fixture_slot(index, true)
		var obstacle_cell := road.origin + definition.rotate_cell(obstacle.cell, road.rotation)
		check(lookup.has("construction_barrier_vault@%s" % obstacle_cell), "%s places deliberate kit barriers only in authored sidewalk slots" % environment_id)

func _check_clear_sidewalk_path(data: MapData, road: EnvironmentModulePlacement, definition: EnvironmentModuleDefinition) -> void:
	for local_cell in [Vector2i(1, 4), Vector2i(8, 4)]:
		var rotated := definition.rotate_cell(local_cell, road.rotation)
		var cell := data.get_cell(Vector3i(road.origin.x + rotated.x, 0, road.origin.y + rotated.y))
		check(cell != null and cell.walkable and cell.can_stop, "The inner sidewalk lane remains a usable pedestrian route")

func _road_cells_preserve_tactical_authority(data: MapData, roads: Array[EnvironmentModulePlacement], catalog: Dictionary) -> bool:
	var barrier_cells: Dictionary = {}
	for placement in data.environment_modules:
		if placement.component_id == &"construction_barrier_vault":
			barrier_cells[Vector3i(placement.origin.x, 0, placement.origin.y)] = true
	for road in roads:
		var definition: EnvironmentModuleDefinition = catalog[road.component_id]
		for local_cell in definition.rotated_cells(definition.footprint_cells, road.rotation):
			var position := Vector3i(road.origin.x + local_cell.x, 0, road.origin.y + local_cell.y)
			var cell := data.get_cell(position)
			if cell == null or not cell.walkable:
				return false
			if barrier_cells.has(position):
				if cell.can_stop or cell.cover_type != MapCellData.CoverType.LOW:
					return false
			elif not cell.can_stop:
				return false
	return true

func _test_presented_sections() -> void:
	var data := FlatMapGenerator.generate_coherent_environment(50, 40, 1.0, 7319, &"commercial_street")
	var presentation := Node3D.new()
	root.add_child(presentation)
	GeneratedTerrainPresenter.build(data, presentation, 1.0)
	var modular_root := presentation.get_node("ModularEnvironment")
	check(modular_root.get_meta("road_presentation_mode", "") == "asset_first", "GeneratedTerrainPresenter explicitly selects asset-first road ownership")
	var streetscapes := presentation.find_children("RoadStreetscape", "Node3D", true, false)
	check(streetscapes.is_empty(), "Normal presentation leaves visible road ownership to the imported kit surfaces")
	var imported_surfaces := 0
	var imported_surface_top := -INF
	for node in presentation.find_children("*", "TacticalVisualOccluder", true, false):
		if node.get_meta("assembly_visual_role", &"") == &"road_surface":
			imported_surfaces += 1
			check(node.get_meta("scale_multiplier", Vector3.ONE).is_equal_approx(Vector3(2, 1, 2)), "Kit road surface uses the authored two-times horizontal streetscape adapter")
			var bounds: AABB = node.global_transform * node.occlusion_bounds
			imported_surface_top = maxf(imported_surface_top, bounds.end.y)
	check(imported_surfaces == data.environment_layout_plan.road_cells.size(), "Every logical road tile presents one reviewed City Roads surface")
	check(is_equal_approx(imported_surface_top, 0.11), "Imported road surfaces resolve to the reviewed 0.11-unit pavement top")
	presentation.queue_free()

	var diagnostics := Node3D.new()
	root.add_child(diagnostics)
	ModularEnvironmentPresenter.build(data, diagnostics, 1.0, ModularEnvironmentPresenter.RoadPresentationMode.DERIVED_DIAGNOSTIC)
	modular_root = diagnostics.get_node("ModularEnvironment")
	check(modular_root.get_meta("road_presentation_mode", "") == "derived_diagnostic", "Derived road reconstruction identifies itself as diagnostic presentation")
	streetscapes = diagnostics.find_children("RoadStreetscape", "Node3D", true, false)
	check(streetscapes.size() == data.environment_layout_plan.road_cells.size(), "Explicit road diagnostics reconstruct every authored cross-section")
	for streetscape in streetscapes:
		check(is_equal_approx(float(streetscape.get_meta("carriageway_width")), 6.0), "Diagnostic streets expose the six-cell carriageway contract")
		check(is_equal_approx(float(streetscape.get_meta("sidewalk_width")), 2.0), "Diagnostic streets expose the two-cell sidewalk contract")
		check(not streetscape.find_children("Asphalt_*", "MeshInstance3D", true, false).is_empty(), "Road diagnostics include pavement")
		check(not streetscape.find_children("Sidewalk_*", "MeshInstance3D", true, false).is_empty(), "Road diagnostics include sidewalks")
	var diagnostic_curb_top := -INF
	for curb: MeshInstance3D in diagnostics.find_children("Curb_*", "MeshInstance3D", true, false):
		diagnostic_curb_top = maxf(diagnostic_curb_top, (curb.global_transform * curb.get_aabb()).end.y)
	check(is_equal_approx(diagnostic_curb_top, Streetscape.CURB_HEIGHT), "Derived diagnostic curbs retain their measured 0.16-unit top")
	check(diagnostic_curb_top > imported_surface_top, "Diagnostic curbs would visibly protrude above imported roads and therefore remain excluded from normal presentation")
	diagnostics.queue_free()

func _section_count(sections: Array[Dictionary], kind: StringName) -> int:
	var count := 0
	for section in sections:
		if section.kind == kind:
			count += 1
	return count

func _has_streetscape_diagnostic(decisions: Array[String]) -> bool:
	for decision in decisions:
		if decision.begins_with("streetscape placed"):
			return true
	return false

func check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
