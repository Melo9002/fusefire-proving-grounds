extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var catalog := IndustrialModuleCatalog.create()
	_test_spatial_contracts(catalog)
	_test_environment_generation(catalog)
	_test_visual_composition(catalog)
	_test_expanded_district_catalog()
	await _test_map_editor()
	print("Coherent layout assembly: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_spatial_contracts(catalog: Dictionary) -> void:
	var clearances := EnvironmentModuleLayout.new(&"clearance_contract", 1)
	var cluster := EnvironmentModulePlacement.new(&"machine_cover_cluster", Vector2i(4, 4))
	check(clearances.try_add(catalog.machine_cover_cluster, cluster, Vector2i(30, 30)), "Machinery cluster establishes its placement contract")
	check(not clearances.try_add(catalog.cargo_container, EnvironmentModulePlacement.new(&"cargo_container", Vector2i(2, 4)), Vector2i(30, 30)), "A tactical footprint cannot intrude into an existing service clearance")

	var envelopes := EnvironmentModuleLayout.new(&"visual_envelope_contract", 2)
	check(envelopes.try_add(catalog.cargo_container, EnvironmentModulePlacement.new(&"cargo_container", Vector2i(2, 2)), Vector2i(30, 30)), "First calibrated visual envelope is accepted")
	check(not envelopes.try_add(catalog.cargo_container, EnvironmentModulePlacement.new(&"cargo_container", Vector2i(4, 2)), Vector2i(30, 30)), "Non-overlapping tactical cells are rejected when calibrated visual envelopes intersect")
	check(envelopes.diagnostics.is_empty(), "Spatial contract checks do not alter tactical state through diagnostics")

func _test_environment_generation(catalog: Dictionary) -> void:
	var first := FlatMapGenerator.generate_coherent_environment(50, 40, 1.0, 2208, &"industrial_district")
	var repeated := FlatMapGenerator.generate_coherent_environment(50, 40, 1.0, 2208, &"industrial_district")
	check(first.environment_layout_plan != null, "Coherent generation publishes a hierarchical layout plan")
	check(_signature(first) == _signature(repeated), "Identical coherent inputs reproduce the same spatial and tactical result")
	check(first.environment_layout_plan.signature() == repeated.environment_layout_plan.signature(), "Road and parcel planning is deterministic")
	check(not first.environment_layout_plan.road_cells.is_empty() and not first.environment_layout_plan.parcels.is_empty(), "The plan separates a road network from parcels")
	check(_roads_are_connected(first, catalog), "Every generated road module belongs to one connected network")
	check(_roads_reach_boundary(first), "Generated road approaches terminate at map boundaries")
	check(_all_parcels_assigned(first.environment_layout_plan), "Every planned parcel receives an authored template or explicit fallback")
	check(_tactical_map_is_valid(first), "The generated district passes shared tactical validation")
	var alternative_seed := FlatMapGenerator.generate_coherent_environment(50, 40, 1.0, 7, &"industrial_district")
	check(not alternative_seed.environment_layout_plan.rejected_candidates.is_empty(), "A constrained seed records a rejected visual or clearance conflict")
	check(not alternative_seed.environment_layout_plan.fallback_used and _tactical_map_is_valid(alternative_seed), "Bounded search selects a valid alternative after rejecting a conflicting parcel template")

	var distinct_signatures: Dictionary = {}
	for environment_id in CoherentEnvironmentAssembler.ENVIRONMENTS:
		for map_seed in [17, 2208, 7319, 11027]:
			var generated := FlatMapGenerator.generate_coherent_environment(50, 40, 1.0, map_seed, environment_id)
			check(generated.source_kind.ends_with(String(environment_id)), "%s preserves its environment identity" % environment_id)
			check(generated.environment_layout_plan.search_attempts <= generated.environment_layout_plan.parcels.size() * CoherentEnvironmentAssembler.MAX_TEMPLATE_ATTEMPTS, "%s seed %d terminates within its bounded parcel search" % [environment_id, map_seed])
			check(_roads_are_connected(generated, catalog), "%s seed %d keeps a connected road network" % [environment_id, map_seed])
			check(_tactical_map_is_valid(generated), "%s seed %d remains a valid tactical battlefield" % [environment_id, map_seed])
			distinct_signatures[_spatial_signature(generated.environment_layout_plan)] = true
	check(distinct_signatures.size() >= 6, "Different seeds and identities change spatial organization, not only prop variants")

func _test_visual_composition(catalog: Dictionary) -> void:
	var data := FlatMapGenerator.generate_coherent_environment(50, 40, 1.0, 7319, &"commercial_street")
	var ids: Dictionary = {}
	for placement in data.environment_modules:
		ids[placement.component_id] = int(ids.get(placement.component_id, 0)) + 1
	for component_id in ids:
		check(not String(component_id).begins_with("industrial_shell_"), "Commercial districts do not misuse industrial-only shell assets")
	check(ids.has(&"complete_service_building"), "Commercial blocks reuse complete four-sided buildings around a shared frontage")
	check(not ids.has(&"factory_shop_front") and not ids.has(&"factory_window_wall"), "Procedural parcels do not expose freestanding facade samples as buildings")
	check(ids.has(&"traffic_signal") and ids.has(&"street_light"), "Commercial road furniture is attached to the street plan")
	var has_large_parcel := false
	for parcel in data.environment_layout_plan.parcels:
		var bounds: Rect2i = parcel.bounds
		if bounds.size.x > CoherentEnvironmentAssembler.MACRO_SIZE or bounds.size.y > CoherentEnvironmentAssembler.MACRO_SIZE:
			has_large_parcel = true
	check(has_large_parcel, "The plot grammar supports authored parcels larger than one macro tile")
	var service_building: EnvironmentModuleDefinition = catalog.complete_service_building
	var exterior_accesses := 0
	for connection in service_building.connections:
		if connection.type == EnvironmentModuleConnection.Type.EXTERIOR_ACCESS:
			exterior_accesses += 1
	check(service_building.assembly_complete and service_building.assembly_enclosure == &"closed", "Procedural service buildings come from a validated closed-building assembly")
	check(exterior_accesses == 4, "Complete service buildings retain the authored four-cell street entrance")
	var presentation := Node3D.new()
	root.add_child(presentation)
	ModularEnvironmentPresenter.build(data, presentation, 1.0)
	var road_surfaces := presentation.find_children("RoadStreetscape", "Node3D", true, false)
	check(road_surfaces.size() == data.environment_layout_plan.road_cells.size(), "Every logical road tile receives a complete derived streetscape")
	for streetscape in road_surfaces:
		check(not streetscape.find_children("Asphalt_*", "MeshInstance3D", true, false).is_empty(), "Every streetscape presents a continuous carriageway")
		check(not streetscape.find_children("Sidewalk_*", "MeshInstance3D", true, false).is_empty(), "Every streetscape presents authored sidewalks")
	presentation.queue_free()

func _test_expanded_district_catalog() -> void:
	var seen_shell_variants: Dictionary = {}
	for environment_id in [&"industrial_district", &"mixed_service"]:
		for map_seed in [2208, 7319]:
			var data := FlatMapGenerator.generate_coherent_environment(60, 50, 1.0, map_seed, environment_id)
			var shell_count := 0
			for placement in data.environment_modules:
				if String(placement.component_id).begins_with("industrial_shell_"):
					shell_count += 1
					seen_shell_variants[placement.component_id] = true
			check(shell_count >= 2, "%s seed %d reserves multiple complete reviewed shell parcels" % [environment_id, map_seed])
	var commercial := FlatMapGenerator.generate_coherent_environment(60, 50, 1.0, 7319, &"commercial_street")
	var commercial_buildings := 0
	for placement in commercial.environment_modules:
		check(not String(placement.component_id).begins_with("industrial_shell_"), "Commercial parcels exclude industrial-only semantic candidates")
		if placement.component_id == &"complete_service_building":
			commercial_buildings += 1
	check(commercial_buildings >= 2, "The expanded commercial district assembles multiple complete street buildings")
	check(seen_shell_variants.size() >= 3, "Representative industrial seeds exercise several reviewed shell assets")

func _test_map_editor() -> void:
	var editor = load("res://tools/map_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	check(editor.preset_picker.item_count == editor.EDITOR_LAYOUTS.size(), "Map Editor offers authored and procedural layouts together")
	editor.layout_preset = &"industrial_district"
	editor.generation_seed = 2208
	editor._rebuild()
	await process_frame
	check(editor.content.get_node_or_null("SpatialPlan") != null, "Map Editor draws the generated road and parcel plan")
	check(editor.preview_map_size == Vector2i(60, 50), "Map Editor frames the expanded coherent-generation canvas")
	check("crossroad" in editor.status.text or "t junction" in editor.status.text, "Map Editor reports topology and generation diagnostics")
	check("VALID" in editor.status.text, "Map Editor validates the procedural sample tactically")
	editor.queue_free()
	await process_frame

func _roads_are_connected(data: MapData, catalog: Dictionary) -> bool:
	var layout := _reconstruct(data, catalog)
	if not layout.errors.is_empty():
		return false
	var roads: Array[EnvironmentModulePlacement] = []
	for placement in layout.placements:
		var definition: EnvironmentModuleDefinition = catalog[placement.component_id]
		if definition.module_type in [EnvironmentModuleDefinition.ModuleType.ROAD, EnvironmentModuleDefinition.ModuleType.INTERSECTION]:
			roads.append(placement)
	if roads.is_empty():
		return false
	var reached: Dictionary = {roads[0]: true}
	var frontier: Array[EnvironmentModulePlacement] = [roads[0]]
	while not frontier.is_empty():
		var current: EnvironmentModulePlacement = frontier.pop_back()
		for neighbor in roads:
			if reached.has(neighbor) or not layout.placements_connect(current, neighbor, catalog):
				continue
			reached[neighbor] = true
			frontier.append(neighbor)
	return reached.size() == roads.size()

func _roads_reach_boundary(data: MapData) -> bool:
	var plan := data.environment_layout_plan
	var reached_edges: Dictionary = {}
	var columns := floori(float(data.map_size.x) / float(plan.macro_size))
	var rows := floori(float(data.map_size.y) / float(plan.macro_size))
	for cell in plan.road_cells:
		if cell.x == 0: reached_edges[Vector2i.LEFT] = true
		if cell.x == columns - 1: reached_edges[Vector2i.RIGHT] = true
		if cell.y == 0: reached_edges[Vector2i.UP] = true
		if cell.y == rows - 1: reached_edges[Vector2i.DOWN] = true
	return reached_edges.size() >= 3

func _all_parcels_assigned(plan: EnvironmentLayoutPlan) -> bool:
	for parcel in plan.parcels:
		if parcel.template == &"unassigned":
			return false
	return true

func _spatial_signature(plan: EnvironmentLayoutPlan) -> String:
	var roads: Array[String] = []
	for road in plan.road_cells:
		roads.append("%d,%d" % [road.x, road.y])
	roads.sort()
	var parcels: Array[String] = []
	for parcel in plan.parcels:
		parcels.append("%s@%s:r%d" % [parcel.template, parcel.bounds.position, parcel.rotation])
	parcels.sort()
	return "%s:%s:%s" % [plan.topology, "|".join(roads), "|".join(parcels)]

func _tactical_map_is_valid(data: MapData) -> bool:
	var graph := Pathfinder.new()
	MapGraphBuilder.build(data, graph)
	return MapValidator.validate(data, graph, {
		TacticalUnit.Faction.PLAYER: 5,
		TacticalUnit.Faction.ENEMY: 5,
	}).is_valid()

func _reconstruct(data: MapData, catalog: Dictionary) -> EnvironmentModuleLayout:
	var result := EnvironmentModuleLayout.new(&"reconstructed", data.environment_module_seed)
	for placement in data.environment_modules:
		if not result.try_add(catalog[placement.component_id], placement, data.map_size):
			break
	return result

func _signature(data: MapData) -> String:
	var modules: Array[String] = []
	for placement in data.environment_modules:
		modules.append(placement.signature())
	var tactical: Array[String] = []
	for cell: MapCellData in data.cells.values():
		if cell.cover_type != MapCellData.CoverType.NONE or not cell.walkable or not cell.can_stop:
			tactical.append("%s:%d:%s:%s" % [cell.grid_position, cell.cover_type, cell.walkable, cell.can_stop])
	modules.sort()
	tactical.sort()
	return "%s#%s" % ["|".join(modules), "|".join(tactical)]

func check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
