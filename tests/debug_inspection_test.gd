extends SceneTree
## Contract: F3 inspects existing authority, without committing actions or rolling RNG.
const Snapshot := preload("res://ui/debug_inspection_snapshot.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	root.size = Vector2i(1280, 720)
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
	await process_frame
	check(level.battle_initialization_succeeded, "Controlled range initializes")
	var battle := level.battle_controller
	battle.set_process(false)
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	var grid := battle.grid_manager
	var actor := level.turn_manager.player_units[0]
	var enemy := level.turn_manager.enemy_units[0]
	for pair in [[actor, Vector3i(1, 0, 16)], [enemy, Vector3i(1, 0, 22)]]:
		var unit: TacticalUnit = pair[0]
		grid.update_unit_position(unit, unit.grid_position, pair[1])
		unit.global_position = grid.grid_to_world(pair[1]) + Vector3.UP * unit.standing_height
	actor.attack_range = 10
	var destination := Vector3i(1, 0, 17)
	var service := battle.action_service
	var tools := level.get_node("Visualizers/BattleUI/DebugTools") as DebugTools
	var ally := level.turn_manager.allied_units[0]
	var shared_context := battle.get_squad_context(actor)
	shared_context.reserve_destination(ally, Vector3i(7, 0, 16))
	level.turn_manager.active_unit = ally
	var ally_snapshot := Snapshot.capture(battle, Vector3i(-1, -1, -1), false)
	check(ally_snapshot.squad.contains("Reservations at F3 open"), "Allied F3 reads the shared player-team context")
	level.turn_manager.active_unit = actor
	var rng := service.get_combat_rng_state()
	var revision := service.state_revision
	var fingerprint := BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager)
	var squad_count := battle._squad_contexts.size()
	var expected_shot := TacticalFeedbackText.shot(battle.query_attack(actor, enemy), true)
	check(battle.query_attack(actor, enemy).is_legal(), "Fixture contains a legal outgoing shot")
	var expected_move := battle.query_move(actor, destination)
	check(expected_move.is_legal(), "Fixture contains a legal hovered move")
	var snapshot := Snapshot.capture(battle, destination, true)
	check(snapshot.targets.size() == 1 and snapshot.targets[0].text.begins_with(expected_shot), "Target text comes from the same authoritative shot prediction")
	check(snapshot.movement.contains("Destination %s" % destination) and snapshot.movement.contains("Path cells"), "Movement snapshot includes the resolved destination and route")
	check(snapshot.unit.contains("Standing point") and snapshot.unit.contains("Within-cell offset") and snapshot.unit.contains("Body radius"), "Unit inspection explains resolved body placement")
	check(snapshot.map.contains("Surface placement") and snapshot.map.contains("Tactical validation: passed"), "Map inspection exposes geometry mode and validation")
	check(snapshot.manifest.contains("population_enabled"), "Optional technical manifest retains accepted choices")
	tools._map_inspector.hovered_cell = grid.get_cell_data(destination)
	tools.set_panel_open(true)
	check(tools._inspection_snapshot.movement.contains("Destination %s" % destination), "F3 captures the inspected destination before pausing")
	check(paused and tools.panel_open, "F3 owns a new pause")
	check(tools._inspection_snapshot.targets[0].text.begins_with(expected_shot), "F3 captures shot legality before pausing")
	check(tools._mission_controller.objective_manager == level.objective_manager, "Developer commands reference this battle's objective manager")
	tools._manifest_toggle.button_pressed = true
	check(tools._inspection_labels["Map"].text.contains("Recorded technical manifest"), "Technical detail is opt-in")
	for section in ["Unit", "Tactical", "AI", "Map", "Runtime", "Diagnostics", "Control", "Mission"]:
		var index := -1
		for child in tools._tabs.get_children():
			if child.name == section: index = child.get_index()
		check(index >= 0, "Section is available: " + section)
		if index < 0: continue
		tools._tabs.current_tab = index
		await process_frame
		await process_frame
		check(Rect2(Vector2.ZERO, tools.get_viewport_rect().size).encloses(tools._panel.get_rect()), "Section fits 1280x720: " + section)
		if section in ["Unit", "Tactical", "Map", "Runtime"]: await _capture(section)
	check(service.state_revision == revision and service.get_combat_rng_state() == rng, "Opening and browsing F3 consumes no revision or RNG")
	check(fingerprint == BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager), "Inspection preserves the complete tactical fingerprint")
	check(squad_count == battle._squad_contexts.size(), "Inspection does not create squad contexts")
	tools._on_debug_mission_command("Test invalidation signal")
	check(tools._inspection_status.text.begins_with("STALE"), "Developer commands visibly invalidate frozen snapshots")
	tools.set_panel_open(false)
	check(not paused, "Closing F3 releases its own pause")
	paused = true
	tools.set_panel_open(true)
	check(tools._inspection_snapshot.targets.is_empty() and tools._inspection_snapshot.movement.contains("already paused"), "Already-paused inspection does not invent live legality")
	tools.set_panel_open(false)
	check(paused, "Closing F3 preserves a pause it did not own")
	paused = false
	battle.replay_mode = true
	tools.set_panel_open(true)
	tools.set_auto_battle(true)
	tools.set_manual_enemy_control(true)
	tools._debug_advance_round()
	check(not tools.panel_open and not paused and not battle.debug_player_ai and not battle.debug_enemy_control, "Replay cannot open or activate live developer controls")
	check(service.get_combat_rng_state() == rng and fingerprint == BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager), "Rejected replay commands preserve authoritative state")
	battle.replay_mode = false
	tools.set_panel_open(true)
	tools.queue_free()
	await process_frame
	await process_frame
	check(not paused, "Removing an open F3 panel releases its owned pause")
	level.queue_free()
	await process_frame
	await process_frame
	print("Debug inspection: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _capture(section: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "capture" or DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute(args[1])
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(args[1].path_join("f3-" + section.to_lower() + ".png")) == OK, "Captured " + section)
