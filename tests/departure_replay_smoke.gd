extends SceneTree

const SCENE := preload("res://levels/prototype_map/prototype_map.tscn")
const SESSION := preload("res://systems/replay/battle_replay_session.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	Engine.time_scale = 8.0
	var level = SCENE.instantiate()
	level.configure(2, 1, true, 23001, 0, Vector2i(24, 20), false, MissionActor.VIPBehavior.PLAYER_CONTROLLED, MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.EXTRACT, 1, false))
	root.add_child(level)
	while level.turn_manager.current_round == 0: await process_frame
	level.action_camera_director.frequency = 0
	level.battle_controller.set_debug_enemy_control(true)
	var unit: TacticalUnit = level.turn_manager.player_units[0]
	var grid: GridManager = level.battle_controller.grid_manager
	var pathfinder: Pathfinder = level.battle_controller.pathfinder
	var destination: Vector3i = grid.map_data.get_objective_zone(&"extract")[0]
	for attempt in 60:
		if level.objective_manager.can_extract(unit): break
		if unit.stats.current_ap == 0 or level.turn_manager.current_phase != TurnManager.TurnPhase.PLAYER_TURN:
			level.turn_manager.end_current_turn()
			await process_frame
			continue
		level.turn_manager.select_player_unit(unit)
		var path := pathfinder.calculate_3d_path(unit.grid_position, destination)
		var reachable := pathfinder.get_reachable_cells(unit.grid_position, unit.stats.speed)
		var goal := Vector3i(-1, -1, -1)
		for point in path:
			var cell := grid.world_to_grid(point)
			if reachable.has(cell) and grid.can_unit_occupy_cell(unit, cell): goal = cell
		if goal.x < 0: break
		check(await level.battle_controller.try_move(unit, goal), "Legal route to boarding")
	check(await level.objective_manager.try_extract(unit), "One unit boards")
	check(level.objective_manager.end_mission_early(), "Transport can leave one unit behind")
	var recording = SESSION.last_recording
	check(recording != null, "Departure stores recording")
	level.queue_free()
	await process_frame
	if recording:
		var replay = SCENE.instantiate()
		replay.configure_replay(recording)
		root.add_child(replay)
		while not replay.has_node("BattleReplayPlayer"): await process_frame
		var player = replay.get_node("BattleReplayPlayer")
		var deadline := Time.get_ticks_msec() + 20000
		while not player.playback_complete and Time.get_ticks_msec() < deadline: await process_frame
		check(player.playback_succeeded, "Departure replay succeeds")
		check(replay.objective_manager.left_behind == 1, "Replay preserves left-behind count")
		replay.queue_free()
		await process_frame
	print("Departure replay: %d failure(s)" % failures)
	quit(1 if failures else 0)
