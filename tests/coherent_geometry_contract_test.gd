extends SceneTree

const Profiles = preload("res://systems/generation/industrial_building_placement_profiles.gd")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_rectangular_envelope_rotation()
	await _test_real_shell_frontage_rotation()
	await _test_imported_road_openings()
	await _test_real_streetlight_facing()
	print("Coherent geometry contracts: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_rectangular_envelope_rotation() -> void:
	var definition := EnvironmentModuleDefinition.new(&"asymmetric_probe", &"test", Vector2i(2, 5))
	definition.set_visual_envelope(AABB(Vector3(-0.25, 0.10, 0.50), Vector3(1.50, 2.0, 3.75)))
	var layout := EnvironmentModuleLayout.new()
	var expected := [
		AABB(Vector3(9.76, 3.11, 20.51), Vector3(1.48, 1.98, 3.73)),
		AABB(Vector3(9.76, 3.11, 19.76), Vector3(3.73, 1.98, 1.48)),
		AABB(Vector3(9.76, 3.11, 19.76), Vector3(1.48, 1.98, 3.73)),
		AABB(Vector3(10.51, 3.11, 19.76), Vector3(3.73, 1.98, 1.48)),
	]
	for rotation in 4:
		var placement := EnvironmentModulePlacement.new(&"asymmetric_probe", Vector2i(10, 20), rotation, 0, 3)
		var actual := layout.world_visual_envelope(definition, placement)
		check(actual.position.is_equal_approx(expected[rotation].position) and actual.size.is_equal_approx(expected[rotation].size), "Rectangular offset envelope r%d follows the independently calculated module transform: expected %s, got %s" % [rotation, expected[rotation], actual])

func _test_real_shell_frontage_rotation() -> void:
	var catalog := IndustrialModuleCatalog.create()
	var definition: EnvironmentModuleDefinition = catalog.industrial_shell_i
	var source_face := Vector3.FORWARD # Reviewed building-i working face is model-local -Z.
	for rotation in 4:
		var visual := await _present_single(definition.component_id, rotation, Vector2i(4, 4))
		check(visual != null, "The real asymmetric building-i asset presents at r%d" % rotation)
		if visual == null:
			continue
		var actual := (visual.basis.orthonormalized() * source_face).normalized()
		var planned_2d := definition.rotate_direction(Vector2i.DOWN, rotation)
		var planned := Vector3(planned_2d.x, 0.0, planned_2d.y)
		check(actual.dot(planned) > 0.999, "Building-i rendered working face agrees with planned frontage at r%d: planned %s, got %s" % [rotation, planned, actual])
		visual.get_parent().get_parent().queue_free()
		await process_frame

func _test_imported_road_openings() -> void:
	var catalog := IndustrialModuleCatalog.create()
	# Source openings come from direct inspection of the imported meshes. They
	# are independent of module connectors and catch missing normalization yaw.
	var cases := [
		{"id": &"road_straight", "origin": Vector2i(4, 4), "source": [Vector3.LEFT, Vector3.RIGHT], "module": [Vector2i.UP, Vector2i.DOWN]},
		{"id": &"road_intersection_t", "origin": Vector2i(4, 4), "source": [Vector3.LEFT, Vector3.RIGHT, Vector3.BACK], "module": [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]},
		{"id": &"road_crossroad", "origin": Vector2i(4, 4), "source": [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK], "module": [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]},
		{"id": &"road_corner", "origin": Vector2i(4, 4), "source": [Vector3.LEFT, Vector3.BACK], "module": [Vector2i.UP, Vector2i.RIGHT]},
	]
	for test_case in cases:
		var definition: EnvironmentModuleDefinition = catalog[test_case.id]
		for rotation in 4:
			var visual := await _present_single(definition.component_id, rotation, test_case.origin)
			check(visual != null, "%s imported road surface presents at r%d" % [test_case.id, rotation])
			if visual == null:
				continue
			var actual: Array[Vector3] = []
			for source_direction: Vector3 in test_case.source:
				actual.append((visual.basis.orthonormalized() * source_direction).normalized())
			var expected: Array[Vector3] = []
			for module_direction: Vector2i in test_case.module:
				var world_direction := definition.rotate_direction(module_direction, rotation)
				expected.append(Vector3(world_direction.x, 0.0, world_direction.y))
			check(_same_direction_set(actual, expected), "%s imported openings agree with logical connectors at r%d: expected %s, got %s" % [test_case.id, rotation, expected, actual])
			visual.get_parent().get_parent().queue_free()
			await process_frame

func _test_real_streetlight_facing() -> void:
	var data := FlatMapGenerator.generate_coherent_environment(50, 40, 1.0, 7319, &"commercial_street")
	var catalog := IndustrialModuleCatalog.create()
	var holder := Node3D.new()
	root.add_child(holder)
	ModularEnvironmentPresenter.build(data, holder, 1.0)
	await process_frame
	var checked := 0
	for module: Node3D in holder.get_node("ModularEnvironment").get_children():
		if module.get_meta("component_id", &"") != &"street_light":
			continue
		var light_origin: Vector2i = module.get_meta("origin")
		var road := _covering_straight_road(data, catalog, light_origin)
		if road == null:
			continue
		var visual: TacticalVisualOccluder
		for child in module.get_children():
			if child is TacticalVisualOccluder:
				visual = child
				break
		check(visual != null, "Streetlight presents its reviewed imported asset")
		if visual == null:
			continue
		var road_definition: EnvironmentModuleDefinition = catalog[road.component_id]
		var axis_2d := road_definition.rotate_direction(Vector2i.DOWN, road.rotation)
		var center := Vector2(road.origin) + Vector2(4.5, 4.5)
		var to_center := center - Vector2(light_origin)
		var lateral := to_center - Vector2(axis_2d) * to_center.dot(Vector2(axis_2d))
		var expected := Vector3(lateral.normalized().x, 0.0, lateral.normalized().y)
		var actual := (visual.basis.orthonormalized() * Vector3.FORWARD).normalized()
		check(actual.dot(expected) > 0.999, "Streetlight model-local -Z faces from its sidewalk toward the carriageway: expected %s, got %s" % [expected, actual])
		checked += 1
	check(checked > 0, "The representative commercial seed exercises final-world streetlight facing in authored road slots")
	holder.queue_free()
	await process_frame

func _covering_straight_road(data: MapData, catalog: Dictionary, cell: Vector2i) -> EnvironmentModulePlacement:
	for placement: EnvironmentModulePlacement in data.environment_modules:
		if placement.component_id != &"road_straight":
			continue
		var definition: EnvironmentModuleDefinition = catalog[placement.component_id]
		var bounds := Rect2i(placement.origin, definition.rotated_size(placement.rotation))
		if bounds.has_point(cell):
			return placement
	return null

func _present_single(component_id: StringName, rotation: int, origin: Vector2i) -> TacticalVisualOccluder:
	var data := FlatMapGenerator.generate(50, 50, 1.0, 1)
	data.environment_modules.append(EnvironmentModulePlacement.new(component_id, origin, rotation))
	var holder := Node3D.new()
	root.add_child(holder)
	ModularEnvironmentPresenter.build(data, holder, 1.0)
	await process_frame
	for candidate in holder.find_children("*", "TacticalVisualOccluder", true, false):
		if candidate.get_meta("assembly_visual_role", &"") == &"road_surface" or candidate.get_meta("assembly_visual_role", &"") == &"structural":
			return candidate as TacticalVisualOccluder
	holder.queue_free()
	return null

func _same_direction_set(actual: Array[Vector3], expected: Array[Vector3]) -> bool:
	if actual.size() != expected.size():
		return false
	var remaining := expected.duplicate()
	for direction in actual:
		var match_index := -1
		for index in remaining.size():
			if direction.dot(remaining[index]) > 0.999:
				match_index = index
				break
		if match_index < 0:
			return false
		remaining.remove_at(match_index)
	return remaining.is_empty()

func check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
