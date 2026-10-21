extends SceneTree

const AssetPlacement = preload("res://presentation/environment_asset_placement.gd")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var data := FlatMapGenerator.generate_modular_environment_sample(40, 30, 1.0, 2303, &"asset_first_frontage")
	var catalog := IndustrialModuleCatalog.create()
	_test_authored_contract(data, catalog)
	await _test_presented_geometry(data)
	print("Asset-first street frontage: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_authored_contract(data: MapData, catalog: Dictionary) -> void:
	check(data.source_kind.ends_with("asset_first_frontage"), "Reference slice identifies its bounded authored preset")
	check(data.environment_modules.size() == 7, "Reference slice contains only the two roads, two pavers, two lights and one shell")
	var layout := EnvironmentModuleLayout.new(&"asset_first_frontage_check", data.environment_module_seed)
	for placement in data.environment_modules:
		check(layout.try_add(catalog[placement.component_id], placement, data.map_size), "Reference placement remains valid: %s at %s" % [placement.component_id, placement.origin])
	var roads := _find_all(data, &"road_straight")
	var paving := _find_all(data, &"paving_square")
	var lights := _find_all(data, &"street_light")
	var building := _find(data, &"industrial_shell_i")
	check(roads.size() == 2 and layout.placements_connect(roads[0], roads[1], catalog), "Imported straight-road modules connect end-to-end")
	for index in mini(roads.size(), paving.size()):
		check(layout.placements_connect(roads[index], paving[index], catalog), "Road segment %d sidewalk connects to its imported paving forecourt" % index)
	check(building != null, "Reference slice uses the reviewed building-i shell")
	if building != null:
		var definition: EnvironmentModuleDefinition = catalog[building.component_id]
		check(definition.assembly_complete and definition.assembly_enclosure == &"prebuilt_shell", "Building-i remains a complete sealed exterior rather than an invented playable interior")
		check(definition.rotate_direction(Vector2i.DOWN, building.rotation) == Vector2i.LEFT, "Building-i logical frontage faces west toward the street")
		var apron := layout.world_clearance_cells(definition, building)
		check(ModularIndustrialLayoutBuilder.REFERENCE_FRONTAGE_ACCESS in apron, "The terminal access cell belongs to the shell's protected frontage apron")
	check(lights.size() == 2 and lights[0].rotation == 3 and lights[1].rotation == 3, "Both streetlights use the reviewed inward-facing authored rotation")

	var graph := Pathfinder.new()
	MapGraphBuilder.build(data, graph)
	var start := Vector3i(ModularIndustrialLayoutBuilder.REFERENCE_ROAD_ACCESS.x, 0, ModularIndustrialLayoutBuilder.REFERENCE_ROAD_ACCESS.y)
	var finish := Vector3i(ModularIndustrialLayoutBuilder.REFERENCE_FRONTAGE_ACCESS.x, 0, ModularIndustrialLayoutBuilder.REFERENCE_FRONTAGE_ACCESS.y)
	for x in range(start.x, finish.x + 1):
		var cell := data.get_cell(Vector3i(x, 0, start.z))
		check(cell != null and cell.walkable and cell.can_stop, "Street-to-frontage access remains unobstructed at x=%d" % x)
	check(not graph.calculate_3d_path(start, finish).is_empty(), "The imported sidewalk has a tactical route across the forecourt to the frontage apron")
	var shell_cell := data.get_cell(Vector3i(24, 0, 14))
	check(shell_cell != null and not shell_cell.walkable and shell_cell.blocks_line_of_sight, "The sealed building remains authoritative blocking MapData beyond the exterior apron")
	var obstructed := EnvironmentModuleLayout.new(&"asset_first_frontage", data.environment_module_seed)
	for placement in data.environment_modules:
		check(obstructed.try_add(catalog[placement.component_id], placement, data.map_size), "Negative access fixture preserves the certified base placement")
	var blocker := EnvironmentModulePlacement.new(&"cargo_container", Vector2i(18, 13))
	check(obstructed.try_add(catalog[blocker.component_id], blocker, data.map_size), "Negative access fixture can place a real obstacle across the forecourt")
	check(not ModularIndustrialLayoutBuilder._validate_asset_first_frontage(obstructed, catalog, data), "Frontage validation rejects an authored obstacle that blocks the access band")

func _test_presented_geometry(data: MapData) -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	GeneratedTerrainPresenter.build(data, holder, 1.0)
	await process_frame
	var modular := holder.get_node("ModularEnvironment") as Node3D
	check(modular.get_meta("road_presentation_mode", "") == "asset_first", "Reference slice uses asset-first road presentation")
	check(holder.find_children("RoadStreetscape", "Node3D", true, false).is_empty(), "No derived asphalt, sidewalk or curb layer covers the imported fixture")
	var road_nodes := _presented_modules(modular, &"road_straight")
	var paving_nodes := _presented_modules(modular, &"paving_square")
	var light_nodes := _presented_modules(modular, &"street_light")
	var building_nodes := _presented_modules(modular, &"industrial_shell_i")
	check(road_nodes.size() == 2 and paving_nodes.size() == 2 and light_nodes.size() == 2 and building_nodes.size() == 1, "Every authored reference component presents exactly once")
	if road_nodes.size() == 2 and paving_nodes.size() == 2:
		var road_bounds := [_visual_bounds(road_nodes[0]), _visual_bounds(road_nodes[1])]
		var paving_bounds := [_visual_bounds(paving_nodes[0]), _visual_bounds(paving_nodes[1])]
		check(is_equal_approx(road_bounds[0].end.z, road_bounds[1].position.z), "Connected imported roads meet at a flush longitudinal seam")
		check(is_equal_approx(paving_bounds[0].end.z, paving_bounds[1].position.z), "Imported forecourt tiles meet without a gap or overlap")
		for index in 2:
			check(is_equal_approx(road_bounds[index].end.x, paving_bounds[index].position.x), "Road sidewalk and paving tile %d meet at the same physical edge" % index)
			check(is_equal_approx(road_bounds[index].end.y, paving_bounds[index].end.y), "Road sidewalk and paving tile %d share the reviewed surface height" % index)
	if paving_nodes.size() == 2 and building_nodes.size() == 1:
		var building_bounds := _visual_bounds(building_nodes[0])
		for paving_node in paving_nodes:
			var paving_bounds := _visual_bounds(paving_node)
			check(is_equal_approx(paving_bounds.end.x, building_bounds.position.x), "Imported paving terminates flush at the building shell")
		var building_visual := _first_visual(building_nodes[0])
		var actual_front := (building_visual.basis.orthonormalized() * Vector3.FORWARD).normalized()
		check(actual_front.dot(Vector3.LEFT) > 0.999, "Rendered building-i working face points toward the street")
	if light_nodes.size() == 2:
		var building_bounds := _visual_bounds(building_nodes[0]) if not building_nodes.is_empty() else AABB()
		for light_node in light_nodes:
			var light_visual := _first_visual(light_node)
			var bounds := light_visual.global_transform * light_visual.occlusion_bounds
			var facing := (light_visual.basis.orthonormalized() * Vector3.FORWARD).normalized()
			var mounted_on_road := false
			for road_node in road_nodes:
				var road_bounds := _visual_bounds(road_node)
				var foot := light_visual.global_position
				if foot.x >= road_bounds.position.x and foot.x <= road_bounds.end.x and foot.z >= road_bounds.position.z and foot.z <= road_bounds.end.z:
					mounted_on_road = true
			check(is_equal_approx(bounds.position.y, 0.11), "Streetlight mounting foot rests on the imported 0.11-unit sidewalk surface")
			check(mounted_on_road, "Streetlight mounting foot lies over an imported road-sidewalk surface")
			check(facing.dot(Vector3.LEFT) > 0.999, "Streetlight head faces inward toward the carriageway")
			check(building_bounds.size == Vector3.ZERO or not bounds.intersects(building_bounds), "Streetlight visible bounds remain clear of the building shell")
	holder.queue_free()
	await process_frame

func _find(data: MapData, id: StringName) -> EnvironmentModulePlacement:
	for placement: EnvironmentModulePlacement in data.environment_modules:
		if placement.component_id == id:
			return placement
	return null

func _find_all(data: MapData, id: StringName) -> Array[EnvironmentModulePlacement]:
	var result: Array[EnvironmentModulePlacement] = []
	for placement: EnvironmentModulePlacement in data.environment_modules:
		if placement.component_id == id:
			result.append(placement)
	return result

func _presented_modules(root_node: Node3D, id: StringName) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for child: Node3D in root_node.get_children():
		if child.get_meta("component_id", &"") == id:
			result.append(child)
	return result

func _first_visual(module: Node3D) -> TacticalVisualOccluder:
	var visuals := module.find_children("*", "TacticalVisualOccluder", true, false)
	return visuals[0] as TacticalVisualOccluder if not visuals.is_empty() else null

func _visual_bounds(module: Node3D) -> AABB:
	var visual := _first_visual(module)
	return visual.global_transform * visual.occlusion_bounds if visual != null else AABB()

func check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
