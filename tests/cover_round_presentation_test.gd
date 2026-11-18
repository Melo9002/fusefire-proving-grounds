extends SceneTree
## Round assets read as round: cover markers hug the real curved wall and pose contacts face it,
## while the tactical data (reserved tiles, cover, shots, standing points) is untouched.
## Rendered review (needs a display): -- capture <directory>
const Pose = preload("res://presentation/characters/runtime/tactical_pose_context.gd")

var failures := 0
var checks := 0

func _initialize() -> void:
	if OS.get_environment("FUSEFIRE_TEST_OUTPUT_DIR").is_empty(): OS.set_environment("FUSEFIRE_TEST_OUTPUT_DIR", ProjectSettings.globalize_path("res://.godot/round-presentation-output"))
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _vertices(mesh: Mesh) -> PackedVector3Array:
	if mesh == null or mesh.get_surface_count() == 0: return PackedVector3Array()
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]

func _run() -> void:
	# Every Service Depot contains the tank storage parcel: one round tank and one lying drum.
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.SERVICE_DEPOT)
	config.battle_seed = 16
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 2)
	var live := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	live.configure_battle(config)
	root.add_child(live)
	check(live.battle_initialization_succeeded, "The Service Depot starts a valid battle")
	if not live.battle_initialization_succeeded:
		live.queue_free()
		quit(1)
		return
	var grid := live.battle_controller.grid_manager
	var data := grid.map_data
	var visualizer := live.battle_controller.cover_visualizer
	check(data.surface_placement_enabled and data.presentation_cylinders.size() == 1 and data.presentation_boxes.size() == 1, "The compiler records one round tank and one lying drum for presentation")
	check(not data.presentation_stand_ins.is_empty(), "The tile-sized stand-ins are remembered so presentation can skip them")
	var tank: CylinderPart = data.presentation_cylinders[0]
	check(is_equal_approx(tank.radius, 3.77104) and tank.height > 4.0, "The tank body radius is the authored 3.77, not the box that includes its pipe (that would be about 3.77-4.12)")

	# Tactical truth is untouched: the stand-ins are still the reserved, blocking, cover-giving tiles.
	var reserved := 0
	for cell: MapCellData in data.cells.values():
		if cell.cover_type == MapCellData.CoverType.FULL and not cell.can_stop and Vector2(cell.support_center.x, cell.support_center.z).distance_to(tank.axis()) < tank.radius - 0.5:
			reserved += 1
	check(reserved > 8, "Tiles inside the tank are still reserved full cover (%d)" % reserved)

	# Destination cells around the tank: every cell a unit could stand in within reach of the wall.
	var around: Array[Vector3i] = []
	for cell: MapCellData in data.cells.values():
		if not cell.can_stop or cell.is_vault_transit: continue
		var distance := Vector2(cell.world_position.x, cell.world_position.z).distance_to(tank.axis())
		if distance > tank.radius and distance < tank.radius + grid.cell_size * SurfaceNavigation.ROUND_REACH_UNITS and absf(cell.world_position.y - tank.center.y) < 0.01:
			around.append(cell.grid_position)
	print("[Round] standing cells within reach of the tank wall: %d" % around.size())
	check(around.size() >= 4, "There are standing cells within reach of the tank wall (%d)" % around.size())
	visualizer.draw_for_cells(around)
	var vertices := _vertices(visualizer._full_mesh.mesh)
	var on_wall := 0
	var worst := 0.0
	var angles := {}
	for vertex in vertices:
		var offset := Vector2(vertex.x, vertex.z) - tank.axis()
		var distance := offset.length()
		# Only the marker vertices belonging to the tank (not the drum or other props).
		if distance < tank.radius - 0.05 or distance > tank.radius + visualizer.edge_width * CoverVisualizer.ARC_BAND_SCALE + 0.05: continue
		on_wall += 1
		var inner := distance - (tank.radius + CoverVisualizer.ARC_WALL_GAP)
		worst = maxf(worst, minf(absf(inner), absf(inner - visualizer.edge_width * CoverVisualizer.ARC_BAND_SCALE)))
		angles[int(floor(rad_to_deg(offset.angle()) / 45.0))] = true
	check(on_wall >= 60, "Many marker vertices lie on the tank wall (%d)" % on_wall)
	check(worst < 0.005, "Every marker vertex sits exactly on the real wall or its band edge; worst deviation %.4f (the tile-box markers were up to about a tile away)" % worst)
	# Every standing cell within reach has a marker on the wall at its own angle.
	var uncovered := 0
	for key in around:
		var cell := grid.get_cell_data(key)
		var outward := (Vector2(cell.world_position.x, cell.world_position.z) - tank.axis()).normalized()
		var wall_point := Vector3(tank.center.x + outward.x * (tank.radius + CoverVisualizer.ARC_WALL_GAP), 0.0, tank.center.z + outward.y * (tank.radius + CoverVisualizer.ARC_WALL_GAP))
		var covered := false
		for vertex in vertices:
			if Vector2(vertex.x, vertex.z).distance_to(Vector2(wall_point.x, wall_point.z)) < 0.2:
				covered = true
				break
		if not covered: uncovered += 1
	check(uncovered == 0, "Every standing cell within reach has a marker on the wall at its own angle (%d without)" % uncovered)
	print("[Round] marker octants around the tank: %d" % angles.size())

	# Pose contacts face the wall at the true radial direction, at any angle.
	var radial_errors: Array[float] = []
	var facing_cardinals := 0
	for key in around:
		var cell := grid.get_cell_data(key)
		var contact := Pose.cover_at(grid, key, Vector3.RIGHT)
		if contact.type == MapCellData.CoverType.NONE or not contact.has("surface_normal"): continue
		var radial := Vector3(cell.world_position.x - tank.center.x, 0, cell.world_position.z - tank.center.z).normalized()
		radial_errors.append(rad_to_deg(acos(clampf(contact.surface_normal.dot(radial), -1.0, 1.0))))
		if absf(contact.surface_normal.x) > 0.999 or absf(contact.surface_normal.z) > 0.999: facing_cardinals += 1
	check(radial_errors.size() == around.size(), "Every cell within reach of the wall gets a wall contact for its pose (%d of %d)" % [radial_errors.size(), around.size()])
	var worst_angle := 0.0
	for error in radial_errors: worst_angle = maxf(worst_angle, error)
	check(worst_angle < 8.0, "Pose contact directions are radial to the wall; worst error %.1f degrees (axis-aligned box faces were up to 45)" % worst_angle)
	print("[Round] pose contacts: %d, axis-aligned: %d, worst radial error %.2f degrees" % [radial_errors.size(), facing_cardinals, worst_angle])
	check(facing_cardinals < radial_errors.size(), "Not every contact is axis-aligned any more (%d of %d are)" % [facing_cardinals, radial_errors.size()])

	# The lying drum is a rectangle from above: its markers follow the true box faces.
	var drum: AABB = data.presentation_boxes[0]
	var drum_cells: Array[Vector3i] = []
	for cell: MapCellData in data.cells.values():
		if not cell.can_stop or cell.is_vault_transit or absf(cell.world_position.y - drum.position.y) > 0.5: continue
		var nearest := Vector2(clampf(cell.world_position.x, drum.position.x, drum.end.x), clampf(cell.world_position.z, drum.position.z, drum.end.z))
		var distance := Vector2(cell.world_position.x, cell.world_position.z).distance_to(nearest)
		if distance > 0.2 and distance < grid.cell_size * 1.2: drum_cells.append(cell.grid_position)
	visualizer.draw_for_cells(drum_cells)
	var drum_vertices := _vertices(visualizer._low_mesh.mesh) + _vertices(visualizer._full_mesh.mesh)
	var on_face := 0
	for vertex in drum_vertices:
		var nearest := Vector2(clampf(vertex.x, drum.position.x, drum.end.x), clampf(vertex.z, drum.position.z, drum.end.z))
		if Vector2(vertex.x, vertex.z).distance_to(nearest) <= visualizer.edge_width + 0.03 and vertex.x > drum.position.x - 0.2 and vertex.x < drum.end.x + 0.2 and vertex.z > drum.position.z - 0.2 and vertex.z < drum.end.z + 0.2: on_face += 1
	check(on_face >= 12, "The drum's markers sit on its real faces (%d vertices)" % on_face)

	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "capture" and DisplayServer.get_name() != "headless":
		await _capture(live, visualizer, tank, around, args[1])
	live.queue_free()
	await process_frame
	print("Round cover presentation: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _capture(live: BattleLevel, visualizer: CoverVisualizer, tank: CylinderPart, around: Array[Vector3i], directory: String) -> void:
	visualizer.draw_for_cells(around)
	var camera := Camera3D.new()
	live.add_child(camera)
	var focus := Vector3(tank.center.x, 1.0, tank.center.z)
	camera.position = focus + Vector3(0.0, 15.0, 11.0)
	camera.look_at(focus)
	camera.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(directory)
	check(root.get_texture().get_image().save_png(directory.path_join("round-cover.png")) == OK, "Capture the round cover view")
