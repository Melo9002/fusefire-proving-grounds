extends SceneTree
## Permanent F3 regression: visual envelopes follow the canonical continuous
## module transform without becoming tactical occupancy.

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_rotation_matrix()
	_test_placement_reservations()
	print("Coherent visual envelopes: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_rotation_matrix() -> void:
	var layout := EnvironmentModuleLayout.new()
	var cases := [
		{"id": &"square_envelope_probe", "size": Vector2i(4, 4), "bounds": AABB(Vector3(0.0, 0.0, 0.0), Vector3(3.5, 2.0, 3.5))},
		{"id": &"rectangular_2x5_probe", "size": Vector2i(2, 5), "bounds": AABB(Vector3(-0.25, 0.10, 0.50), Vector3(1.50, 2.0, 3.75))},
		{"id": &"rectangular_4x3_probe", "size": Vector2i(4, 3), "bounds": AABB(Vector3(-1.10, -0.40, 0.20), Vector3(5.25, 3.20, 1.60))},
	]
	for test_case in cases:
		var definition := EnvironmentModuleDefinition.new(test_case.id, &"test", test_case.size)
		var local_envelope: AABB = test_case.bounds
		definition.set_visual_envelope(local_envelope)
		for rotation in 4:
			var placement := EnvironmentModulePlacement.new(test_case.id, Vector2i(10, 20), rotation, 0, 3)
			var actual := layout.world_visual_envelope(definition, placement)
			var expected := _independent_world_envelope(local_envelope, definition.size, placement)
			check(actual.position.is_equal_approx(expected.position) and actual.size.is_equal_approx(expected.size), "%s r%d follows independently transformed corners: expected %s, got %s" % [test_case.id, rotation, expected, actual])

func _test_placement_reservations() -> void:
	var primary := EnvironmentModuleDefinition.new(&"visual_primary", &"test", Vector2i(2, 5))
	primary.footprint_cells.clear() # Isolate visual reservation from tactical cells.
	primary.set_visual_envelope(AABB(Vector3(-0.25, 0.10, 0.50), Vector3(1.50, 2.0, 3.75)))
	var blocker := EnvironmentModuleDefinition.new(&"visual_blocker", &"test", Vector2i.ONE)
	blocker.footprint_cells.clear()
	blocker.set_visual_envelope(AABB(Vector3.ZERO, Vector3.ONE))

	# At r2 the corrected primary occupies X 9.76..11.24. The old defective
	# transform displaced it to X 12.76..14.24.
	var collision_layout := EnvironmentModuleLayout.new(&"visual_collision", 1)
	check(collision_layout.try_add(primary, EnvironmentModulePlacement.new(primary.component_id, Vector2i(10, 10), 2), Vector2i(30, 30)), "Corrected r2 primary visual reservation is accepted")
	var collision_rejected := not collision_layout.try_add(blocker, EnvironmentModulePlacement.new(blocker.component_id, Vector2i(10, 10)), Vector2i(30, 30))
	check(collision_rejected, "Visible r2 intersection is rejected by the corrected visual reservation")
	if collision_rejected:
		check(not collision_layout.errors.is_empty() and collision_layout.errors.back().contains("visual envelope intersects"), "Visual collision reports the visual-envelope contract rather than tactical occupancy")

	var separation_layout := EnvironmentModuleLayout.new(&"visual_separation", 2)
	check(separation_layout.try_add(primary, EnvironmentModulePlacement.new(primary.component_id, Vector2i(10, 10), 2), Vector2i(30, 30)), "Separated r2 primary visual reservation is accepted")
	check(separation_layout.try_add(blocker, EnvironmentModulePlacement.new(blocker.component_id, Vector2i(12, 10)), Vector2i(30, 30)), "Legitimate placement outside the corrected r2 envelope is not rejected by the old displaced region")
	check(separation_layout.world_cells(primary, separation_layout.placements[0]).is_empty(), "Visual reservation does not create tactical footprint cells")

	var seam_layout := EnvironmentModuleLayout.new(&"visual_seam", 3)
	check(seam_layout.try_add(blocker, EnvironmentModulePlacement.new(blocker.component_id, Vector2i(5, 5)), Vector2i(30, 30)), "First seam-control envelope is accepted")
	check(seam_layout.try_add(blocker, EnvironmentModulePlacement.new(blocker.component_id, Vector2i(6, 5)), Vector2i(30, 30)), "Face-touching visual envelopes remain compatible after the intentional epsilon shrink")

func _independent_rotate_point(point: Vector2, module_size: Vector2i, rotation: int) -> Vector2:
	match posmod(rotation, 4):
		1: return Vector2(float(module_size.y - 1) - point.y, point.x)
		2: return Vector2(float(module_size.x - 1) - point.x, float(module_size.y - 1) - point.y)
		3: return Vector2(point.y, float(module_size.x - 1) - point.x)
		_: return point

func _independent_world_envelope(local: AABB, module_size: Vector2i, placement: EnvironmentModulePlacement) -> AABB:
	var world_points: Array[Vector3] = []
	for x in [local.position.x, local.end.x]:
		for y in [local.position.y, local.end.y]:
			for z in [local.position.z, local.end.z]:
				var horizontal := _independent_rotate_point(Vector2(x, z), module_size, placement.rotation)
				world_points.append(Vector3(horizontal.x + placement.origin.x, y + placement.elevation, horizontal.y + placement.origin.y))
	var expected := AABB(world_points[0], Vector3.ZERO)
	for point in world_points:
		expected = expected.expand(point)
	# Match the documented seam tolerance only after independently calculating
	# the unshrunk bounds from all eight corners.
	return expected.grow(-0.01) if expected.size.x > 0.02 and expected.size.y > 0.02 and expected.size.z > 0.02 else expected

func check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
