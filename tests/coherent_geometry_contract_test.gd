extends SceneTree

const Profiles = preload("res://systems/generation/industrial_building_placement_profiles.gd")
const AssetCatalog = preload("res://tools/asset_lab/asset_catalog.gd")
const AssetPlacement = preload("res://presentation/environment_asset_placement.gd")

const ROAD_BOUNDARY_SAMPLES := 101
const ROAD_SURFACE_Y_TOLERANCE := 0.0015

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_canonical_quarter_turn_table()
	_test_connector_placement_uses_contract()
	_test_connected_road_fixture()
	await _test_real_shell_frontage_rotation()
	await _test_imported_road_openings()
	await _test_road_surface_height_alignment()
	await _test_real_streetlight_facing()
	print("Coherent geometry contracts: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_canonical_quarter_turn_table() -> void:
	var definition := EnvironmentModuleDefinition.new(&"transform_probe", &"test", Vector2i(3, 2))
	var expected_directions := [Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT]
	var expected_points := [Vector2(0.25, 0.75), Vector2(0.25, 0.25), Vector2(1.75, 0.25), Vector2(0.75, 1.75)]
	var expected_world_directions := [Vector3.BACK, Vector3.LEFT, Vector3.FORWARD, Vector3.RIGHT]
	for rotation in 4:
		check(definition.rotate_direction(Vector2i.DOWN, rotation) == expected_directions[rotation], "Canonical r%d maps local +Z to grid %s" % [rotation, expected_directions[rotation]])
		check(definition.rotate_point(Vector2(0.25, 0.75), rotation).is_equal_approx(expected_points[rotation]), "Canonical r%d maps the rectangular local point to %s" % [rotation, expected_points[rotation]])
		var rendered_direction := Basis(Vector3.UP, definition.placement_yaw_radians(rotation)) * Vector3.BACK
		check(rendered_direction.is_equal_approx(expected_world_directions[rotation]), "Canonical r%d Godot yaw maps local +Z to world %s" % [rotation, expected_world_directions[rotation]])

func _test_connector_placement_uses_contract() -> void:
	var definition := EnvironmentModuleDefinition.new(&"connector_probe", &"test", Vector2i(3, 2))
	definition.add_connection(Vector2i(2, 1), Vector2i.DOWN, EnvironmentModuleConnection.Type.ROAD)
	var layout := EnvironmentModuleLayout.new()
	var expected_cells := [Vector2i(12, 21), Vector2i(10, 22), Vector2i(10, 20), Vector2i(11, 20)]
	var expected_directions := [Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT]
	for rotation in 4:
		var placement := EnvironmentModulePlacement.new(&"connector_probe", Vector2i(10, 20), rotation)
		var connections := layout.world_connections(definition, placement)
		check(connections.size() == 1, "Canonical connector probe produces one world connection at r%d" % rotation)
		if connections.size() != 1:
			continue
		check(connections[0].cell == expected_cells[rotation], "Canonical connector r%d cell: expected %s, got %s" % [rotation, expected_cells[rotation], connections[0].cell])
		check(connections[0].direction == expected_directions[rotation], "Canonical connector r%d direction: expected %s, got %s" % [rotation, expected_directions[rotation], connections[0].direction])

func _test_connected_road_fixture() -> void:
	var catalog := IndustrialModuleCatalog.create()
	var layout := EnvironmentModuleLayout.new(&"road_orientation_fixture", 1404)
	var placements := {
		"cross": EnvironmentModulePlacement.new(&"road_crossroad", Vector2i(25, 20)),
		"north_near": EnvironmentModulePlacement.new(&"road_straight", Vector2i(25, 10)),
		"north_far": EnvironmentModulePlacement.new(&"road_straight", Vector2i(25, 0)),
		"west": EnvironmentModulePlacement.new(&"road_straight", Vector2i(15, 20), 1),
		"east": EnvironmentModulePlacement.new(&"road_straight", Vector2i(35, 20), 1),
		"curve": EnvironmentModulePlacement.new(&"road_corner", Vector2i(20, 30)),
		"curve_exit": EnvironmentModulePlacement.new(&"road_straight", Vector2i(40, 35), 1),
	}
	for key in placements:
		var placement: EnvironmentModulePlacement = placements[key]
		check(layout.try_add(catalog[placement.component_id], placement, Vector2i(60, 55)), "Road fixture accepts %s without overlap" % key)
	var joins := [
		["north_far", "north_near"],
		["north_near", "cross"],
		["west", "cross"],
		["cross", "east"],
		["cross", "curve"],
		["curve", "curve_exit"],
	]
	for join in joins:
		check(layout.placements_connect(placements[join[0]], placements[join[1]], catalog), "Road fixture connector seam %s -> %s is logically compatible" % [join[0], join[1]])

func _test_real_shell_frontage_rotation() -> void:
	var catalog := IndustrialModuleCatalog.create()
	var definition: EnvironmentModuleDefinition = catalog.industrial_shell_i
	var source_face := Vector3.FORWARD # Reviewed building-i working face is model-local -Z.
	# These are the authored logical frontages for local DOWN at rotations 0..3.
	# Keeping the oracle explicit avoids repeating either Godot yaw or production
	# rotate_direction math in the expected result.
	var expected_frontages := [Vector3.BACK, Vector3.LEFT, Vector3.FORWARD, Vector3.RIGHT]
	for rotation in 4:
		var visual := await _present_single(definition.component_id, rotation, Vector2i(4, 4))
		check(visual != null, "The real asymmetric building-i asset presents at r%d" % rotation)
		if visual == null:
			continue
		var actual := (visual.basis.orthonormalized() * source_face).normalized()
		var planned: Vector3 = expected_frontages[rotation]
		check(actual.dot(planned) > 0.999, "Building-i rendered working face agrees with planned frontage at r%d: planned %s, got %s" % [rotation, planned, actual])
		visual.get_parent().get_parent().queue_free()
		await process_frame

func _test_imported_road_openings() -> void:
	var catalog := IndustrialModuleCatalog.create()
	var cases := [
		{"id": &"road_straight", "asset_id": "city_kit_roads/road-straight", "origin": Vector2i(4, 4), "module": [Vector2i.UP, Vector2i.DOWN]},
		{"id": &"road_intersection_t", "asset_id": "city_kit_roads/road-intersection", "origin": Vector2i(4, 4), "module": [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]},
		{"id": &"road_crossroad", "asset_id": "city_kit_roads/road-crossroad", "origin": Vector2i(4, 4), "module": [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]},
		{"id": &"road_corner", "asset_id": "city_kit_roads/road-curve", "origin": Vector2i(4, 4), "module": [Vector2i.UP, Vector2i.RIGHT]},
	]
	for test_case in cases:
		var definition: EnvironmentModuleDefinition = catalog[test_case.id]
		var source_openings := _source_road_openings(test_case.asset_id)
		check(source_openings.size() == test_case.module.size(), "%s physical mesh exposes %d road openings, matching its %d authored connector directions: got %s" % [test_case.asset_id, source_openings.size(), test_case.module.size(), source_openings])
		for rotation in 4:
			if rotation not in definition.allowed_rotations:
				continue # An unsupported authored configuration is outside this contract.
			var visual := await _present_single(definition.component_id, rotation, test_case.origin)
			check(visual != null, "%s imported road surface presents at r%d" % [test_case.id, rotation])
			if visual == null:
				continue
			var actual: Array[Vector3] = []
			for source_direction: Vector3 in source_openings:
				actual.append((visual.basis.orthonormalized() * source_direction).normalized())
			var expected: Array[Vector3] = []
			for module_direction: Vector2i in test_case.module:
				var world_direction := _independent_rotate_direction(module_direction, rotation)
				expected.append(Vector3(world_direction.x, 0.0, world_direction.y))
			check(_same_direction_set(actual, expected), "%s imported openings agree with logical connectors at r%d: expected %s, got %s" % [test_case.id, rotation, expected, actual])
			visual.get_parent().get_parent().queue_free()
			await process_frame

func _test_road_surface_height_alignment() -> void:
	var component_ids := [&"road_straight", &"road_intersection_t", &"road_crossroad", &"road_corner"]
	var expected_top := NAN
	for component_id in component_ids:
		var visual := await _present_single(component_id, 0, Vector2i(4, 4))
		check(visual != null, "%s presents for physical seam-height inspection" % component_id)
		if visual == null:
			continue
		var world_bounds: AABB = visual.global_transform * visual.occlusion_bounds
		if is_nan(expected_top):
			expected_top = world_bounds.end.y
		check(is_equal_approx(world_bounds.end.y, expected_top), "%s pavement top aligns with the straight-road seam height: expected %.3f, got %.3f" % [component_id, expected_top, world_bounds.end.y])
		visual.get_parent().get_parent().queue_free()
		await process_frame

func _source_road_openings(asset_id: String) -> Array[Vector3]:
	var scene := load(AssetCatalog.path_for(asset_id)).instantiate() as Node3D
	if scene == null:
		return []
	var bounds := AssetPlacement.mesh_bounds(scene)
	var top_triangles: Array[PackedVector2Array] = []
	_collect_top_triangles(scene, Transform3D.IDENTITY, bounds.end.y, top_triangles)
	var result: Array[Vector3] = []
	var directions := [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]
	for direction in directions:
		if _boundary_has_road_opening(bounds, direction, top_triangles):
			result.append(direction)
	scene.free()
	return result

func _collect_top_triangles(node: Node, accumulated: Transform3D, top_y: float, result: Array[PackedVector2Array]) -> void:
	var transform := accumulated
	if node is Node3D:
		transform = accumulated * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			if mesh_instance.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var triangle_count := indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
			for triangle_index in triangle_count:
				var points := PackedVector3Array()
				for corner in 3:
					var vertex_index := indices[triangle_index * 3 + corner] if not indices.is_empty() else triangle_index * 3 + corner
					points.append(transform * vertices[vertex_index])
				if absf(points[0].y - top_y) > ROAD_SURFACE_Y_TOLERANCE or absf(points[1].y - top_y) > ROAD_SURFACE_Y_TOLERANCE or absf(points[2].y - top_y) > ROAD_SURFACE_Y_TOLERANCE:
					continue
				result.append(PackedVector2Array([
					Vector2(points[0].x, points[0].z),
					Vector2(points[1].x, points[1].z),
					Vector2(points[2].x, points[2].z),
				]))
	for child in node.get_children():
		_collect_top_triangles(child, transform, top_y, result)

func _boundary_has_road_opening(bounds: AABB, direction: Vector3, top_triangles: Array[PackedVector2Array]) -> bool:
	var covered := PackedByteArray()
	var inset := minf(bounds.size.x, bounds.size.z) * 0.002
	for sample_index in ROAD_BOUNDARY_SAMPLES:
		var ratio := float(sample_index) / float(ROAD_BOUNDARY_SAMPLES - 1)
		var point: Vector2
		if direction == Vector3.LEFT:
			point = Vector2(bounds.position.x + inset, lerpf(bounds.position.z, bounds.end.z, ratio))
		elif direction == Vector3.RIGHT:
			point = Vector2(bounds.end.x - inset, lerpf(bounds.position.z, bounds.end.z, ratio))
		elif direction == Vector3.FORWARD:
			point = Vector2(lerpf(bounds.position.x, bounds.end.x, ratio), bounds.position.z + inset)
		else:
			point = Vector2(lerpf(bounds.position.x, bounds.end.x, ratio), bounds.end.z - inset)
		covered.append(1 if _point_on_top_surface(point, top_triangles) else 0)
	var index := 1
	while index < covered.size() - 1:
		if covered[index] != 0:
			index += 1
			continue
		var start := index
		while index < covered.size() and covered[index] == 0:
			index += 1
		var bounded := covered[start - 1] != 0 and index < covered.size() and covered[index] != 0
		var gap_ratio := float(index - start) / float(ROAD_BOUNDARY_SAMPLES - 1)
		# Square tiles expose a 0.6-wide opening across a 1.0 edge. The
		# two-pitch curve exposes the same 0.8 opening across a 2.0 edge.
		if bounded and gap_ratio >= 0.35 and gap_ratio <= 0.90:
			return true
	return false

func _point_on_top_surface(point: Vector2, triangles: Array[PackedVector2Array]) -> bool:
	for triangle in triangles:
		var a := triangle[0]
		var b := triangle[1]
		var c := triangle[2]
		var area := _cross_2d(b - a, c - a)
		if absf(area) < 0.000001:
			continue
		var first := _cross_2d(b - a, point - a)
		var second := _cross_2d(c - b, point - b)
		var third := _cross_2d(a - c, point - c)
		if (first >= -0.00001 and second >= -0.00001 and third >= -0.00001) or (first <= 0.00001 and second <= 0.00001 and third <= 0.00001):
			return true
	return false

func _cross_2d(first: Vector2, second: Vector2) -> float:
	return first.x * second.y - first.y * second.x

func _independent_rotate_direction(direction: Vector2i, rotation: int) -> Vector2i:
	match posmod(rotation, 4):
		1: return Vector2i(-direction.y, direction.x)
		2: return Vector2i(-direction.x, -direction.y)
		3: return Vector2i(direction.y, -direction.x)
		_: return direction

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
