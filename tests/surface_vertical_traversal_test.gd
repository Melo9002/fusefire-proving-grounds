extends SceneTree
## Authored links may leave floor support, but geometry and presentation must
## share a swept route around the upper slab rather than cut through it.
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
	check(level.battle_initialization_succeeded, "The current range initializes with surface fitting enabled")
	if not level.battle_initialization_succeeded: level.free(); quit(1); return
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	var grid := level.battle_controller.grid_manager
	var data := grid.map_data
	var low := Vector3i(12, 0, 4)
	var high := Vector3i(12, 3, 5)
	var from := grid.grid_to_world(low)
	var to := grid.grid_to_world(high)
	var route := SurfaceNavigation.traversal_route(data, from, to)
	check(route.size() == 3, "Authored ladder supplies rise-outside-then-step-on route")
	check(not SurfaceNavigation._sweep_clear(data, from, to, false), "A direct diagonal would hit the upper slab")
	check(SurfaceNavigation.edge_clear(data, from, to) and SurfaceNavigation.edge_clear(data, to, from), "Shared checked route clears the slab in both directions")
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	grid.update_unit_position(actor, actor.grid_position, low)
	actor.global_position = from + Vector3.UP * actor.standing_height
	check(await level.battle_controller.try_move(actor, high), "Real Move climbs the authored ladder")
	check(actor.current_path.size() == 3, "Presentation follows the same three-point route")
	check(actor.grid_position == high and actor.global_position.is_equal_approx(to + Vector3.UP * actor.standing_height), "Climb ends at canonical supported point")
	check(await level.battle_controller.try_move(actor, low), "Real Move descends the checked route")
	check(actor.grid_position == low and actor.global_position.is_equal_approx(from + Vector3.UP * actor.standing_height), "Descent restores lower supported point")
	var graph := level.battle_controller.pathfinder
	for x in [6, 11]:
		var steps: Array[Vector3i] = [Vector3i(x, 0, 15), Vector3i(x, 1, 14), Vector3i(x, 2, 13), Vector3i(x, 3, 12)]
		for index in range(1, steps.size()):
			check(graph.astar.are_points_connected(graph.grid_to_id_map[steps[index - 1]], graph.grid_to_id_map[steps[index]]) and SurfaceNavigation.edge_clear(data, grid.grid_to_world(steps[index - 1]), grid.grid_to_world(steps[index])), "Authored ramp/stair step remains directly usable, without a ladder detour")
	grid.update_unit_position(actor, actor.grid_position, Vector3i(11, 0, 15))
	actor.global_position = grid.grid_to_world(actor.grid_position) + Vector3.UP * actor.standing_height
	check(await level.battle_controller.try_move(actor, Vector3i(11, 3, 12)), "Real Move traverses the existing authored ramp")
	check(actor.current_path.size() == 7 and actor.grid_position == Vector3i(11, 3, 12), "Ramp presentation follows every validated rise/step checkpoint")
	level.turn_manager.action_completion_barrier = func(): return true
	level.turn_manager._advance_exhausted_unit_if_needed(actor.get_instance_id())
	check(process_frame.is_connected(level.turn_manager._advance_exhausted_unit_if_needed.bind(actor.get_instance_id())), "Pending exhaustion work belongs to the manager and is canceled on teardown")
	level.free()
	await process_frame
	print("Surface vertical traversal: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
