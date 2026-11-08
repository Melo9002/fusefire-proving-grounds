extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var level = load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(5, 5)
	root.add_child(level)
	await create_timer(0.15).timeout

	var battle: BattleController = level.battle_controller
	var grid: GridManager = battle.grid_manager
	check(grid.map_floor.size == Vector3(32, 1, 24), "Battlefield is 32 by 24 tiles")
	check(grid.map_data.cells.size() == 876, "Map data contains ground, platforms, ramp, and stair cells")
	for obstacle in level.get_node("Environment/Obstacles").get_children():
		var minimum = obstacle.position - obstacle.size * 0.5
		var maximum = obstacle.position + obstacle.size * 0.5
		check(is_equal_approx(minimum.x, roundf(minimum.x)) and is_equal_approx(maximum.x, roundf(maximum.x)), "%s aligns with x grid lines" % obstacle.name)
		check(is_equal_approx(minimum.z, roundf(minimum.z)) and is_equal_approx(maximum.z, roundf(maximum.z)), "%s aligns with z grid lines" % obstacle.name)
	for surface_node in level.get_tree().get_nodes_in_group("elevated_surfaces"):
		var minimum = surface_node.position - surface_node.size * 0.5
		var maximum = surface_node.position + surface_node.size * 0.5
		check(is_equal_approx(minimum.x, roundf(minimum.x)) and is_equal_approx(maximum.x, roundf(maximum.x)), "%s aligns with x grid lines" % surface_node.name)
		check(is_equal_approx(minimum.z, roundf(minimum.z)) and is_equal_approx(maximum.z, roundf(maximum.z)), "%s aligns with z grid lines" % surface_node.name)

	var low_count := 0
	var full_count := 0
	for cell in grid.map_data.cells.values():
		if cell.cover_type == MapCellData.CoverType.LOW:
			low_count += 1
			check(cell.walkable and not cell.can_stop and cell.movement_cost == 2, "Low cover is configured for vaulting")
		elif cell.cover_type == MapCellData.CoverType.FULL:
			full_count += 1
			check(not cell.walkable and not cell.can_stop and cell.blocks_line_of_sight, "Full cover blocks traversal and LOS")
	check(low_count > 10, "Battlefield contains several low-cover approaches")
	print("Battlefield cover cells: low=", low_count, " full=", full_count)
	check(full_count > 10, "Battlefield contains substantial full-cover walls")

	var ladder_bottom := Vector3i(7, 0, 6)
	var ladder_top := Vector3i(7, 2, 5)
	var platform_center := Vector3i(8, 2, 4)
	check(grid.get_cell_data(platform_center) != null and grid.get_cell_data(platform_center).can_stop, "Platform top is regular walkable terrain")
	check(not grid.get_cell_data(Vector3i(8, 0, 4)).walkable, "Platform body blocks its ground footprint")
	check(grid.world_to_grid(grid.grid_to_world(platform_center)) == platform_center, "Platform clicks resolve to the elevated cell")
	check(grid.map_data.traversal_links.size() == 4, "Every authored ladder becomes reusable MapData")
	check(battle.pathfinder.calculate_3d_path(ladder_bottom, ladder_top).size() == 2, "Ladder explicitly connects its floor and platform cells")
	check(not battle.pathfinder.calculate_3d_path(ladder_bottom, platform_center).is_empty(), "Platform uses normal pathfinding after the ladder")

	var lower_deck := Vector3i(8, 2, 3)
	var upper_deck := Vector3i(8, 5, 3)
	check(grid.map_data.has_cell(lower_deck) and grid.map_data.has_cell(upper_deck), "Stacked decks share X/Z with independent elevation cells")
	check(grid.get_cell_data(lower_deck).can_stop and grid.get_cell_data(upper_deck).can_stop, "Both stacked decks are valid destinations")
	check(not battle.pathfinder.calculate_3d_path(Vector3i(7, 2, 5), Vector3i(7, 5, 4)).is_empty(), "The upper-deck ladder joins both platform levels")

	var high_platform := Vector3i(16, 4, 3)
	check(grid.get_cell_data(high_platform) != null and grid.get_cell_data(high_platform).can_stop, "The elevation-four platform is ordinary walkable terrain")
	check(not battle.pathfinder.calculate_3d_path(Vector3i(14, 0, 9), high_platform).is_empty(), "The ramp reaches the high platform")
	check(not battle.pathfinder.calculate_3d_path(Vector3i(18, 0, 9), high_platform).is_empty(), "The stairs reach the high platform")
	check(not battle.pathfinder.calculate_3d_path(Vector3i(16, 0, 0), high_platform).is_empty(), "The ladder independently reaches the high platform")
	for elevation_path_node in level.get_tree().get_nodes_in_group("elevation_paths"):
		var heights = (elevation_path_node as ElevationPath).get_cells().map(func(cell: Vector3i) -> int: return cell.y)
		check(heights == [1, 2, 3, 4], "%s contributes a continuous elevation sequence" % elevation_path_node.name)

	for unit in level.turn_manager.player_units + level.turn_manager.enemy_units:
		var spawn_cell = grid.world_to_grid(unit.global_position)
		check(grid.map_data.has_cell(spawn_cell), "%s spawns inside the map" % unit.name)
		check(grid.get_cell_data(spawn_cell).can_stop, "%s spawns on valid floor" % unit.name)

	for player in level.turn_manager.player_units:
		for enemy in level.turn_manager.enemy_units:
			var start = grid.world_to_grid(player.global_position)
			var target = grid.world_to_grid(enemy.global_position)
			check(not battle.pathfinder.calculate_3d_path(start, target).is_empty(), "%s can reach %s" % [player.name, enemy.name])

	for route in [Vector3(-4.5, 0, -11.5), Vector3(0.5, 0, 0.5), Vector3(0.5, 0, 11.5)]:
		check(grid.get_cell_data(grid.world_to_grid(route)).can_stop, "North, center, and south crossings remain open")

	var sedan := level.get_node("Environment/Obstacles/ParkedSedan") as CSGBox3D
	var cargo := level.get_node("Environment/Obstacles/StackedCargo") as CSGBox3D
	for prop in [sedan, cargo]:
		var proxy := AABB(-prop.size * 0.5, prop.size)
		for neighbor: CSGBox3D in prop.get_parent().get_children():
			if neighbor == prop:
				continue
			var neighbor_bounds := AABB(neighbor.position - neighbor.size * 0.5, neighbor.size)
			check(not (prop.transform * proxy).intersects(neighbor_bounds), "%s leaves %s clear" % [prop.name, neighbor.name])
		for visual in prop.get_children():
			var bounds := EnvironmentAssetPlacement.mesh_bounds(visual)
			check(proxy.grow(0.005).encloses(bounds), "%s imported visual fits its authored volume" % visual.name)
		var center := grid.world_to_grid(Vector3(prop.position.x, 0, prop.position.z))
		check(not grid.get_cell_data(center).can_stop and grid.get_cell_data(center).blocks_line_of_sight, "%s remains solid in MapData" % prop.name)
	var rig := level.get_node("CameraRig") as TacticalCamera
	rig.set_process(false)
	rig._cancel_selection_focus()
	rig.camera.global_position = Vector3(18, 39, 34)
	rig.camera.look_at(Vector3.ZERO)
	rig.camera.fov = 43.0
	await _capture("test-range-overview")
	var actor: TacticalUnit = level.turn_manager.active_unit
	var behind_car := Vector3i(26, 0, 15)
	grid.update_unit_position(actor, actor.grid_position, behind_car)
	actor.global_position = grid.grid_to_world(behind_car) + Vector3.UP * actor.standing_height
	rig.camera.global_position = actor.global_position + Vector3(0, 0.2, 4.7)
	rig.camera.look_at(actor.global_position)
	await _capture("test-range-vehicle-solid")
	var car_mesh := sedan.find_children("*", "MeshInstance3D", true, false)[0]
	rig._update_camera_occlusion(0.2)
	check(rig._environment_apertures.active.has(car_mesh), "The authored vehicle bay tests the shared local camera cutout")
	var blocker := CombatRules.get_blocking_cell(rig.camera.global_position, actor.global_position, grid)
	check(blocker != null and blocker.grid_position.x == behind_car.x and blocker.grid_position.z in range(16, 19), "The car still blocks tactical LOS through the cutout")
	await _capture("test-range-vehicle-cutout")
	level.queue_free()
	await process_frame
	print("Battlefield layout smoke: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _capture(view: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "capture" or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(args[1])
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(args[1].path_join(view + ".png")) == OK, "Captured %s" % view)
