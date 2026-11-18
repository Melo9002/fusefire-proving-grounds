extends SceneTree
# A physically legal carrier destination can still be forbidden by squad intent.
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
class ProbeAI extends AIController:
	var destinations: Array[Vector3i] = []
	func _legal_move_destinations() -> Array[Vector3i]: return destinations
	func _get_hostile_units() -> Array[TacticalUnit]: return []

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.TACTICAL_TEST_RANGE)
	config.player_count = 1
	config.enemy_count = 1
	config.ally_count = 1
	config.content_manifest = {"population_enabled": false}
	level.configure_battle(config)
	root.add_child(level)
	await process_frame
	var battle := level.battle_controller
	battle.debug_player_ai = true
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	var outcomes: Array[Dictionary] = []
	battle.ai_action_outcome_recorded.connect(func(record: Dictionary): outcomes.append(record))
	var actor := level.turn_manager.player_units[0]
	var other := level.turn_manager.enemy_units[0]
	var ally := level.turn_manager.allied_units[0]
	var squad := battle.get_squad_context(actor)
	squad.begin_round(99)
	var grid := battle.grid_manager
	var start := Vector3i(1, 0, 16)
	var candidate := Vector3i(1, 0, 17)
	var goal := Vector3i(1, 0, 18)
	grid.update_unit_position(actor, actor.grid_position, start)
	actor.global_position = grid.grid_to_world(start) + Vector3.UP * actor.standing_height
	actor.carried_unit = other # Only sets the carrier predicate; no action is submitted.
	squad.reserve_destination(ally, candidate)
	var ai := ProbeAI.new()
	ai.unit = actor
	ai.turn_manager = level.turn_manager
	ai.battle_controller = battle
	level.add_child(ai)
	ai._squad_context = squad
	ai.destinations = [candidate]
	ai.current_mission_intent.kind = MissionIntent.Kind.EXTRACT
	var path := battle.pathfinder.calculate_3d_path(start, goal)
	check(path.size() == 3 and grid.can_unit_occupy_cell(actor, candidate), "Reserved tile is physically legal on a real carrier route")
	var moved := await ai._move_along_goal_path(path, start, goal, false)
	check(not moved and actor.grid_position == start, "Carrier rejects a hard reservation without moving")
	check(ai._last_position_candidates.size() == 1 and ai._last_position_candidates[0].status == "rejected", "Hard reservation has an explicit rejected candidate record")
	ai.destinations = [candidate, goal]
	check(await ai._move_along_goal_path(path, start, goal, false), "Carrier retains an unreserved forward alternative")
	check(actor.grid_position == goal, "Alternative commits through authoritative movement")
	check(outcomes.size() == 1 and outcomes[0].stage == "committed" and outcomes[0].decision_id > 0, "Selected movement links to the committed transaction")
	check(outcomes[0].transaction_id > 0 and outcomes[0].committed_revision > outcomes[0].base_revision, "Outcome carries authoritative transaction and revisions")
	ai._publish_movement_preview(Vector3i(99, 0, 99), "Invalid destination regression")
	check(not await battle.try_move(actor, Vector3i(99, 0, 99)), "Invalid move remains rejected")
	check(outcomes.size() == 2 and outcomes[1].stage == "rejected" and outcomes[1].decision_id > outcomes[0].decision_id and outcomes[1].has("reason"), "Rejected selection has its own linked outcome and reason")
	var replacement_exit := Vector3i(1, 0, 23)
	grid.map_data.set_objective_zone(&"extract", [replacement_exit])
	ai._committed_carrier_route = [goal, Vector3i(1, 0, 25)]
	var refreshed_route := ai._carrier_route(actor)
	check(refreshed_route.has(replacement_exit) and not refreshed_route.has(Vector3i(1, 0, 25)), "Changed extraction invalidates the carrier's cached endpoint")
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "capture" and DisplayServer.get_name() != "headless":
		var tools := level.get_node("Visualizers/BattleUI/DebugTools") as DebugTools
		tools.set_panel_open(true)
		tools._tabs.current_tab = 2
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(args[1])
		check(root.get_texture().get_image().save_png(args[1].path_join("f3-rejected-move.png")) == OK, "Capture real rejected movement inspection")
		tools.set_panel_open(false)
	actor.carried_unit = null
	level.queue_free()
	await process_frame
	print("Carrier reservations: %d failures" % failures)
	quit(1 if failures else 0)
