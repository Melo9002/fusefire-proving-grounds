extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	for dimensions in FlatMapGenerator.MAP_SIZES:
		for map_seed in range(1, 101):
			var data := FlatMapGenerator.generate_with_cover(dimensions.x, dimensions.y, 1.0, map_seed)
			var repeated := FlatMapGenerator.generate_with_cover(dimensions.x, dimensions.y, 1.0, map_seed)
			check(not data.containers.is_empty(), "Each supported size supplies containers")
			check(data.containers == repeated.containers, "Container footprints reproduce by seed")
			var graph := Pathfinder.new()
			MapGraphBuilder.build(data, graph)
			check(MapValidator.validate(data, graph).is_valid(), "Container map remains connected")
			var occupied: Dictionary = {}
			for footprint in data.containers:
				for x in range(footprint.position.x, footprint.end.x):
					for z in range(footprint.position.y, footprint.end.y):
						var position := Vector3i(x, 0, z)
						check(not occupied.has(position), "Container footprints do not overlap")
						occupied[position] = true
						var cell := data.get_cell(position)
						check(cell != null and not cell.walkable and cell.blocks_line_of_sight, "Container cells block movement and LOS")
		var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
		var config := BattleConfiguration.new()
		config.player_count = 5
		config.enemy_count = 5
		config.ally_count = 5
		config.generated_map = true
		config.battle_seed = 12345
		config.map_size = dimensions
		config.select_battlefield(BattlefieldCatalog.GENERATED_COVER)
		level.configure_battle(config)
		root.add_child(level)
		await create_timer(0.2).timeout
		var grid := level.battle_controller.grid_manager
		check(grid.map_data.cells.size() >= dimensions.x * dimensions.y, "Runtime map includes the requested ground dimensions")
		check(grid.map_floor.size.x == dimensions.x and grid.map_floor.size.z == dimensions.y, "Floor follows map size")
		check(grid.occupancy_map.size() == 15, "All teams fit each map size")
		var camera := level.get_node("CameraRig") as TacticalCamera
		camera.global_position = Vector3(999, 0, 999)
		camera._clamp_to_map()
		check(is_equal_approx(camera.global_position.x, dimensions.x * 0.5 + camera.map_margin), "Camera bounds follow resized map")
		level.queue_free()
		await process_frame
	print("Container maps: 300 seeds across three sizes; %d failures" % failures)
	quit(1 if failures else 0)
