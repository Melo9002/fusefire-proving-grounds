extends SceneTree
## Preserve vaulting while making its physical checkpoint authoritative.
var failures := 0
var checks := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _run() -> void:
	Engine.time_scale = 12
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.TACTICAL_TEST_RANGE)
	config.player_count = 1
	config.enemy_count = 1
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	await process_frame
	check(level.battle_initialization_succeeded, "Current range initializes")
	if not level.battle_initialization_succeeded: level.free(); quit(1); return
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	var grid := level.battle_controller.grid_manager
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var start := Vector3i(21, 0, 9)
	var barrier := Vector3i(21, 0, 10)
	var end := Vector3i(21, 0, 11)
	grid.update_unit_position(actor, actor.grid_position, start)
	actor.global_position = grid.grid_to_world(start) + Vector3.UP * actor.standing_height
	var transit := grid.get_cell_data(barrier)
	check(transit.is_vault_transit and transit.walkable and not transit.can_stop, "Low cover remains traversable but never a stopping destination")
	var query := level.battle_controller.query_move(actor, end)
	check(query.is_legal() and query.path_cells == [start, barrier, end], "The real Move query crosses the costed low-cover checkpoint")
	if query.is_legal():
		check(query.presentation_path[1].is_equal_approx(transit.world_position + Vector3.UP * actor.standing_height), "Animation does not add cover height twice")
		check(SurfaceNavigation.body_clear(grid.map_data, transit.world_position), "The canonical airborne checkpoint clears the physical barrier")
		check(await level.battle_controller.try_move(actor, end), "A real Move vaults the barrier")
		check(actor.grid_position == end and actor.global_position.is_equal_approx(grid.grid_to_world(end) + Vector3.UP * actor.standing_height), "Actor lands at its canonical destination")
		check(actor.current_path.size() == 5, "Presentation rises, crosses and lands on the validated route")
	level.free()
	await process_frame
	var data := TacticalMapBuilder.generate(8, 8, 1, 17)
	var wall := Node3D.new()
	wall.position = Vector3(1, 0.4, 0.5)
	wall.set_meta("solid_size", Vector3(0.12, 0.8, 3))
	AuthoredSceneMapCompiler.compile(wall, data, 1)
	wall.free()
	MapGraphBuilder.build(data, Pathfinder.new())
	var a := Vector3(0.5, 0, 0.5)
	var b := Vector3(1.5, 0, 0.5)
	check(SurfaceNavigation.traversal_route(data, a, b).size() == 4 and SurfaceNavigation.edge_clear(data, a, b), "A low tile-edge barrier can be vaulted between two free standing cells")
	data.movement_parts.append(AABB(Vector3(0, 1.9, 0), Vector3(2, 0.4, 1)))
	check(SurfaceNavigation.body_clear(data, a) and not SurfaceNavigation.edge_clear(data, a, b), "Standing headroom does not imply headroom for a vault")
	print("Surface vault: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
