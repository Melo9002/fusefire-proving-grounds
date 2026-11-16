extends SceneTree
## Current default must fix ordinary crate/container placement without asset flags.
const Library = preload("res://tools/parcel_editor/parcel_placement_library.gd")
const Compiler = preload("res://systems/generation2/authored_scene_map_compiler.gd")
var failures := 0
var checks := 0

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	for asset in ["factory_kit/box-large", "city_kit_industrial/shipping-container-a"]:
		for turn in 4:
			var scene := Node3D.new()
			scene.transform = Transform3D(Basis(Vector3.UP, turn * PI * 0.5), Vector3(0.5, 0, 0.5))
			var object := Library.create(asset)
			scene.add_child(object)
			var current := TacticalMapBuilder.generate(16, 16, 1, 17)
			var previous := TacticalMapBuilder.generate(16, 16, 1, 17)
			Compiler.compile(scene, current, 1)
			Compiler.compile(scene, previous, 1, Transform3D.IDENTITY, true, 5)
			scene.free()
			var graph := Pathfinder.new()
			MapGraphBuilder.build(current, graph)
			var direction: Vector3i = [Vector3i.LEFT, Vector3i.BACK, Vector3i.RIGHT, Vector3i.FORWARD][turn]
			var key := Vector3i(8, 0, 8) + direction
			var cell := current.get_cell(key)
			check(current.surface_placement_enabled and current.surface_points_resolved, "Default compiler finalizes %s without per-asset/map opt-in" % asset)
			check(not previous.get_cell(key).can_stop and cell.can_stop, "%s turn %d opens the formerly reserved neighbor" % [asset, turn])
			check(not cell.world_position.is_equal_approx(cell.support_center) and SurfaceNavigation.body_clear(current, cell.world_position), "The ordinary asset gets a real safe standing offset")
			check(not graph.calculate_3d_path(key + direction, key).is_empty(), "A swept route can reach the new standing point")
			var closest := INF
			for surface in SurfaceNavigation.cover_surfaces(current, cell.world_position):
				var contact := SurfacePlacement.contact(cell.world_position, surface.authored_shot_bounds)
				if contact.found: closest = minf(closest, contact.distance)
			check(absf(closest - 0.32) < 0.0002, "Standing body reaches the real face with .04 clearance")
	for site in BattlefieldCatalog.PLAYABLE:
		for seed_value in [16, 17]:
			var data := BattlefieldCatalog.generate(site, Vector2i.ZERO, seed_value, 1)
			check(data.generation_errors.is_empty() and data.surface_placement_enabled, "%s seed %d enables the same current workflow: %s" % [site, seed_value, data.generation_errors])
			var graph := Pathfinder.new()
			MapGraphBuilder.build(data, graph)
			check(MapValidator.validate(data, graph).is_valid(), "All current site deployments and graph invariants remain valid")
			check(data.content_manifest.has("standing_points_signature"), "Normal maps record within-cell reconstruction evidence")
	var round_data := TacticalMapBuilder.generate(16, 16, 1, 17)
	var tank := Node3D.new()
	tank.position = Vector3(0.5, 2, 0.5)
	tank.set_meta("solid_size", Vector3(4, 4, 4))
	tank.set_meta("round_volume", true)
	Compiler.compile(tank, round_data, 1)
	tank.free()
	var tank_graph := Pathfinder.new()
	MapGraphBuilder.build(round_data, tank_graph)
	check(round_data.get_cell(Vector3i(6, 0, 6)).can_stop, "Rounded fallback does not turn the entire enclosing rectangle into a wall")
	check(not SurfaceNavigation.cover_surfaces(round_data, round_data.get_cell(Vector3i(5, 0, 8)).world_position).is_empty(), "Rounded fallback retains its conservative cover surfaces")
	var pocket := TacticalMapBuilder.generate(16, 16, 1, 17)
	pocket.surface_placement_enabled = true
	pocket.movement_parts.assign([AABB(Vector3(-0.4315, 0, -1.5565), Vector3(1.863, 1.7404, 4.113)), AABB(Vector3(-0.4315, 0, 3.4435), Vector3(1.863, 1.7404, 4.113))])
	SurfaceNavigation.resolve_map(pocket, 1)
	var inside := pocket.get_cell(Vector3i(8, 0, 10))
	var outside := pocket.get_cell(Vector3i(7, 0, 10))
	check(inside.can_stop and outside.can_stop and SurfaceNavigation.body_clear(pocket, inside.world_position) and SurfaceNavigation.body_clear(pocket, outside.world_position), "Both ends of the between-container gap have actual clearance")
	check(not SurfaceNavigation._sweep_clear(pocket, inside.world_position, outside.world_position, true), "The straight line would cut the container corner")
	check(SurfaceNavigation.traversal_route(pocket, inside.world_position, outside.world_position).size() == 3 and SurfaceNavigation.edge_clear(pocket, inside.world_position, outside.world_position), "A checked within-edge elbow connects the otherwise isolated gap")
	await _capture_regular_depot()
	print("Surface rollout: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _capture_regular_depot() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "capture" or DisplayServer.get_name() == "headless": return
	Engine.time_scale = 12
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.SERVICE_DEPOT)
	config.battle_seed = 16
	config.player_count = 1
	config.enemy_count = 1
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	await process_frame
	check(level.battle_initialization_succeeded, "Regular Depot initializes for visual review")
	if not level.battle_initialization_succeeded: level.free(); return
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	var grid := level.battle_controller.grid_manager
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	for name in ["CrateA", "ContainerEast"]:
		var object := level.find_child(name, true, false) as Node3D
		var volume := object.get_node("TacticalVolume") as Node3D
		var dimensions: Vector3 = volume.get_meta("solid_size")
		var bounds := volume.global_transform * AABB(-dimensions * 0.5, dimensions)
		var options: Array[MapCellData] = []
		for cell: MapCellData in grid.map_data.cells.values():
			if not cell.can_stop or cell.world_position.is_equal_approx(cell.support_center): continue
			var contact := SurfacePlacement.contact(cell.world_position, bounds)
			if contact.found and absf(contact.distance - 0.32) < 0.0002: options.append(cell)
		options.sort_custom(func(a: MapCellData, b: MapCellData): return a.world_position.distance_squared_to(bounds.get_center()) < b.world_position.distance_squared_to(bounds.get_center()))
		check(not options.is_empty(), name + " has a close shifted point in the regular map")
		if options.is_empty(): continue
		var target := options[0].grid_position
		var start := Vector3i(-1, -1, -1)
		for direction in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
			var candidate: Vector3i = target + direction
			if grid.can_unit_occupy_cell(actor, candidate) and SurfaceNavigation.edge_clear(grid.map_data, grid.grid_to_world(candidate), grid.grid_to_world(target)):
				start = candidate
				break
		check(start.x >= 0, name + " has a checked approach")
		if start.x < 0: continue
		# Fixture setup only: approach itself goes through the real Move action.
		grid.update_unit_position(actor, actor.grid_position, start)
		actor.global_position = grid.grid_to_world(start) + Vector3.UP * actor.standing_height
		check(await level.battle_controller.try_move(actor, target), name + " is reachable in the regular map")
		var camera := level.get_node("CameraRig") as TacticalCamera
		camera.focus_position(actor.global_position)
		camera._manual_pitch = true
		camera.rotation = Vector3(deg_to_rad(-45), deg_to_rad(-30), 0)
		camera._set_zoom(14)
		level.battle_controller.cover_visualizer.draw_for_cells([target])
		for frame in 30: await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(args[1])
		check(root.get_texture().get_image().save_png(args[1].path_join(name + ".png")) == OK, "Capture regular " + name)
	level.free()
	await process_frame
