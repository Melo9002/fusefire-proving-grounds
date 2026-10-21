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
	await _test_supported_fixture_rotations(catalog)
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

func _test_supported_fixture_rotations(catalog: Dictionary) -> void:
	# The expected tables are explicit certification oracles. They do not call
	# the production direction/yaw helpers whose agreement is under test.
	var road_join_directions := [Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT]
	var frontage_directions := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
	var rendered_frontages := [Vector3.LEFT, Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK]
	for rotation in 4:
		var data := _rotated_fixture(rotation, catalog)
		var repeated := _rotated_fixture(rotation, catalog)
		check(_map_signature(data) == _map_signature(repeated), "r%d reproduces identical placements and tactical cells" % rotation)
		var start_cell := _rotate_square_cell(ModularIndustrialLayoutBuilder.REFERENCE_ROAD_ACCESS, rotation)
		var finish_cell := _rotate_square_cell(ModularIndustrialLayoutBuilder.REFERENCE_FRONTAGE_ACCESS, rotation)
		var graph := Pathfinder.new()
		MapGraphBuilder.build(data, graph)
		check(not graph.calculate_3d_path(Vector3i(start_cell.x, 0, start_cell.y), Vector3i(finish_cell.x, 0, finish_cell.y)).is_empty(), "r%d preserves tactical sidewalk-to-frontage access" % rotation)

		var holder := Node3D.new()
		root.add_child(holder)
		GeneratedTerrainPresenter.build(data, holder, 1.0)
		await process_frame
		var modular := holder.get_node("ModularEnvironment") as Node3D
		check(holder.find_children("RoadStreetscape", "Node3D", true, false).is_empty(), "r%d keeps derived visible road layers disabled" % rotation)
		var road_nodes := _presented_modules(modular, &"road_straight")
		var paving_nodes := _presented_modules(modular, &"paving_square")
		var light_nodes := _presented_modules(modular, &"street_light")
		var building_nodes := _presented_modules(modular, &"industrial_shell_i")
		if road_nodes.size() == 2 and paving_nodes.size() == 2 and building_nodes.size() == 1:
			var first_road := _visual_bounds(road_nodes[0])
			var second_road := _visual_bounds(road_nodes[1])
			check(_face_gap(first_road, second_road, road_join_directions[rotation]) <= 0.001, "r%d connected roads meet at their physical opening plane" % rotation)
			check(is_equal_approx(first_road.end.y, second_road.end.y), "r%d connected road surface heights agree" % rotation)
			var building_bounds := _visual_bounds(building_nodes[0])
			for index in 2:
				var road_bounds := _visual_bounds(road_nodes[index])
				var paving_bounds := _visual_bounds(paving_nodes[index])
				check(_face_gap(road_bounds, paving_bounds, frontage_directions[rotation]) <= 0.001, "r%d road/paving transition %d has no physical gap" % [rotation, index])
				check(is_equal_approx(road_bounds.end.y, paving_bounds.end.y), "r%d road/paving transition %d shares its surface height" % [rotation, index])
				check(_face_gap(paving_bounds, building_bounds, frontage_directions[rotation]) <= 0.001, "r%d paving terminates at the physical building frontage" % rotation)
			var building_visual := _first_visual(building_nodes[0])
			var actual_front := (building_visual.basis.orthonormalized() * Vector3.FORWARD).normalized()
			check(actual_front.dot(rendered_frontages[rotation]) > 0.999, "r%d building frontage has the expected final world direction" % rotation)
		var layout := _reconstruct_layout(data, catalog)
		for module in building_nodes + light_nodes:
			var placement := _placement_at(data, module.get_meta("component_id"), module.get_meta("origin"))
			var definition: EnvironmentModuleDefinition = catalog[placement.component_id]
			var approved := _grid_bounds_to_world(data, layout.world_visual_envelope(definition, placement))
			var actual := _visual_bounds(module)
			check(_contains_with_tolerance(approved, actual, 0.021), "r%d %s rendered geometry remains inside its approved envelope" % [rotation, placement.component_id])
		if not building_nodes.is_empty():
			var building_bounds := _visual_bounds(building_nodes[0])
			for light_node in light_nodes:
				var light_visual := _first_visual(light_node)
				var facing := (light_visual.basis.orthonormalized() * Vector3.FORWARD).normalized()
				check(facing.dot(rendered_frontages[rotation]) > 0.999, "r%d streetlight heads face the rotated carriageway" % rotation)
				check(not _visual_bounds(light_node).intersects(building_bounds), "r%d streetlight geometry maintains building clearance" % rotation)
		var rendered_signature := _presentation_signature(modular)
		holder.queue_free()
		await process_frame

		var repeated_holder := Node3D.new()
		root.add_child(repeated_holder)
		GeneratedTerrainPresenter.build(repeated, repeated_holder, 1.0)
		await process_frame
		check(rendered_signature == _presentation_signature(repeated_holder.get_node("ModularEnvironment")), "r%d reproduces identical resolved asset transforms and bounds" % rotation)
		repeated_holder.queue_free()
		await process_frame

func _rotated_fixture(rotation: int, catalog: Dictionary) -> MapData:
	var source := FlatMapGenerator.generate_modular_environment_sample(40, 40, 1.0, 2303, &"asset_first_frontage")
	var result := FlatMapGenerator.generate(40, 40, 1.0, 2303)
	var layout := EnvironmentModuleLayout.new(&"asset_first_frontage_r%d" % rotation, 2303)
	for placement: EnvironmentModulePlacement in source.environment_modules:
		var definition: EnvironmentModuleDefinition = catalog[placement.component_id]
		var placed_size := definition.rotated_size(placement.rotation)
		var rotated_origin := _rotate_square_rect_origin(placement.origin, placed_size, rotation)
		var rotated := EnvironmentModulePlacement.new(placement.component_id, rotated_origin, posmod(placement.rotation + rotation, 4), placement.variation, placement.elevation)
		check(layout.try_add(definition, rotated, result.map_size), "r%d accepts transformed %s at %s" % [rotation, placement.component_id, rotated.origin])
	EnvironmentModuleMapWriter.apply(result, layout, catalog, 1.0)
	result.source_kind = "certification_asset_first_frontage_r%d" % rotation
	result.environment_modules.assign(layout.placements)
	result.environment_module_seed = 2303
	result.rebuild_los_index()
	return result

func _rotate_square_rect_origin(origin: Vector2i, size: Vector2i, rotation: int) -> Vector2i:
	match rotation:
		1: return Vector2i(40 - origin.y - size.y, origin.x)
		2: return Vector2i(40 - origin.x - size.x, 40 - origin.y - size.y)
		3: return Vector2i(origin.y, 40 - origin.x - size.x)
		_: return origin

func _rotate_square_cell(cell: Vector2i, rotation: int) -> Vector2i:
	match rotation:
		1: return Vector2i(39 - cell.y, cell.x)
		2: return Vector2i(39 - cell.x, 39 - cell.y)
		3: return Vector2i(cell.y, 39 - cell.x)
		_: return cell

func _face_gap(first: AABB, second: AABB, direction: Vector2i) -> float:
	match direction:
		Vector2i.RIGHT: return absf(first.end.x - second.position.x)
		Vector2i.LEFT: return absf(first.position.x - second.end.x)
		Vector2i.DOWN: return absf(first.end.z - second.position.z)
		Vector2i.UP: return absf(first.position.z - second.end.z)
	return INF

func _reconstruct_layout(data: MapData, catalog: Dictionary) -> EnvironmentModuleLayout:
	var layout := EnvironmentModuleLayout.new(&"certification_reconstruction", data.environment_module_seed)
	for placement: EnvironmentModulePlacement in data.environment_modules:
		check(layout.try_add(catalog[placement.component_id], placement, data.map_size), "Certification reconstruction accepts %s" % placement.component_id)
	return layout

func _grid_bounds_to_world(data: MapData, bounds: AABB) -> AABB:
	var origin := data.get_cell(Vector3i.ZERO).world_position
	return AABB(bounds.position + Vector3(origin.x, 0.0, origin.z), bounds.size)

func _contains_with_tolerance(outer: AABB, inner: AABB, tolerance: float) -> bool:
	return inner.position.x >= outer.position.x - tolerance and inner.position.y >= outer.position.y - tolerance and inner.position.z >= outer.position.z - tolerance \
		and inner.end.x <= outer.end.x + tolerance and inner.end.y <= outer.end.y + tolerance and inner.end.z <= outer.end.z + tolerance

func _placement_at(data: MapData, id: StringName, origin: Vector2i) -> EnvironmentModulePlacement:
	for placement: EnvironmentModulePlacement in data.environment_modules:
		if placement.component_id == id and placement.origin == origin:
			return placement
	return null

func _map_signature(data: MapData) -> String:
	var placements: Array[String] = []
	for placement: EnvironmentModulePlacement in data.environment_modules:
		placements.append(placement.signature())
	var cells: Array[String] = []
	for cell: MapCellData in data.cells.values():
		if not cell.walkable or cell.cover_type != MapCellData.CoverType.NONE or cell.blocks_line_of_sight:
			cells.append("%s:%s:%d:%s" % [cell.grid_position, cell.walkable, cell.cover_type, cell.blocks_line_of_sight])
	placements.sort()
	cells.sort()
	return "%s#%s" % ["|".join(placements), "|".join(cells)]

func _presentation_signature(modular: Node3D) -> String:
	var entries: Array[String] = []
	for module: Node3D in modular.get_children():
		for visual: TacticalVisualOccluder in module.find_children("*", "TacticalVisualOccluder", true, false):
			var bounds: AABB = visual.global_transform * visual.occlusion_bounds
			entries.append("%s:%s:%s:%s:%s" % [module.get_meta("component_id"), module.get_meta("origin"), module.get_meta("rotation"), visual.get_meta("asset_path"), _quantized_bounds(bounds)])
	entries.sort()
	return "|".join(entries)

func _quantized_bounds(bounds: AABB) -> String:
	var values := [bounds.position.x, bounds.position.y, bounds.position.z, bounds.size.x, bounds.size.y, bounds.size.z]
	var result: Array[String] = []
	for value: float in values:
		result.append(str(roundi(value * 1000000.0)))
	return ",".join(result)

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
