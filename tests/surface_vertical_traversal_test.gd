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
	# The ramp contract (Movement Foundations 03): a declared ramp is presented as continuous travel along its REAL slope. Judged against the physical surface (physics rays on the
	# authored CSG), not against a waypoint count: the committed cell and AP are the tactical ones, the walk stays on the surface, the only vertical step is the one the authored
	# geometry has (a step up onto the exit deck at the end of the ramp), and the path never goes backwards or below that surface.
	var space := level.get_world_3d().direct_space_state
	var ramp_ap_before := actor.stats.current_ap
	var ramp_query: Dictionary = level.battle_controller._query_move_data(actor, Vector3i(11, 3, 12))
	var finished := []
	var walk_ramp := func() -> void:
		finished.append(await level.battle_controller.try_move(actor, Vector3i(11, 3, 12)))
	walk_ramp.call()
	var float_most := 0.0
	var sink_most := 0.0
	var guard := 0
	while finished.is_empty() and guard < 2000:
		guard += 1
		await process_frame
		var feet := actor.global_position - Vector3.UP * actor.standing_height
		if absf(feet.z - grid.grid_to_world(Vector3i(11, 3, 12)).z - 0.5) < 0.07:
			continue   # the lip plane, where the unit steps from the ramp's end onto the deck
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(feet.x, 8.0, feet.z), Vector3(feet.x, -2.0, feet.z), 2))
		if not hit.is_empty():
			float_most = maxf(float_most, feet.y - hit.position.y)
			sink_most = minf(sink_most, feet.y - hit.position.y)
	check(bool(finished[0]) and actor.grid_position == Vector3i(11, 3, 12), "Real Move traverses the existing authored ramp and ends on its committed cell")
	check(actor.global_position.is_equal_approx(grid.grid_to_world(Vector3i(11, 3, 12)) + Vector3.UP * actor.standing_height), "The unit ends exactly on the destination floor point")
	check(float_most < 0.02 and sink_most > -0.02, "The ramp is walked on its physical surface: float %.3f m, sink %.3f m (the old vertical-then-level route floated up to 1 m)" % [float_most, sink_most])
	check(float(ramp_query.path_cost) == 3.0 and ramp_ap_before - actor.stats.current_ap == 1, "The tactical cost is unchanged: three one-step links (path cost %.1f) and one action (%d AP)" % [float(ramp_query.path_cost), ramp_ap_before - actor.stats.current_ap])
	var walked := actor.current_path
	var vertical := 0
	var backwards := false
	var monotone := true
	for i in range(1, walked.size()):
		var horizontal := Vector2(walked[i].x - walked[i - 1].x, walked[i].z - walked[i - 1].z)
		if horizontal.length() < 0.01 and absf(walked[i].y - walked[i - 1].y) > 0.05:
			vertical += 1
			check(absf(walked[i].y - walked[i - 1].y) < 0.55, "The one vertical step is the authored lip, about half a metre (%.2f m)" % absf(walked[i].y - walked[i - 1].y))
		if walked[i].y < walked[i - 1].y - 0.001:
			monotone = false
		if walked[i].z > walked[i - 1].z + 0.001:
			backwards = true   # the ramp climbs toward -z
	check(vertical == 1 and monotone and not backwards, "The presented route climbs steadily toward the exit with exactly one vertical step (%d), never backwards" % vertical)
	check(walked[walked.size() - 1].is_equal_approx(grid.grid_to_world(Vector3i(11, 3, 12)) + Vector3.UP * actor.standing_height), "The presented route ends at the committed destination")
	level.turn_manager.action_completion_barrier = func(): return true
	level.turn_manager._advance_exhausted_unit_if_needed(actor.get_instance_id())
	check(process_frame.is_connected(level.turn_manager._advance_exhausted_unit_if_needed.bind(actor.get_instance_id())), "Pending exhaustion work belongs to the manager and is canceled on teardown")
	level.free()
	await process_frame
	print("Surface vertical traversal: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
