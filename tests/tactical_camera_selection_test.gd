extends SceneTree

const BATTLE_SCENE := preload("res://levels/prototype_map/prototype_map.tscn")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var config := BattleConfiguration.new()
	config.player_count = 3
	config.enemy_count = 1
	config.battle_seed = 7104
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 1, false)
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	while level.turn_manager.current_round == 0: await process_frame
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	var rig := level.get_node("CameraRig") as TacticalCamera
	# OS pointer state is irrelevant to this signal/tween fixture.
	rig.set_process(false)
	rig.selection_focus_duration = 0.08
	rig.comfortable_viewport_margin = 0.4
	await create_timer(0.2).timeout
	var units := level.turn_manager.player_units
	var first := units[0]
	var second := units[1]
	var third := units[2]
	var zoom_before := rig._zoom
	var rotation_before := rig.rotation
	rig.global_position = first.global_position
	check(level.turn_manager.select_player_unit(second), "Manual selection succeeds")
	check(rig.is_selection_focus_active(), "Manual selection starts the shared camera transition")
	await create_timer(0.2).timeout
	check(rig.global_position.distance_to(rig._clamped_focus_position(second.global_position)) < 0.05, "Manual selection centers the selected unit")
	check(is_equal_approx(rig._zoom, zoom_before) and rig.rotation.is_equal_approx(rotation_before), "Selection focus preserves zoom and viewing angle")

	# A rapid replacement kills the old tween and lands on the latest selection.
	rig.global_position = Vector3.ZERO
	level.turn_manager.select_player_unit(first)
	level.turn_manager.select_player_unit(third)
	await create_timer(0.2).timeout
	check(rig.global_position.distance_to(rig._clamped_focus_position(third.global_position)) < 0.05, "Rapid selection follows the latest requested unit")

	# Manual movement owns the camera immediately and cancels automatic motion.
	rig.global_position = Vector3.ZERO
	level.turn_manager.select_player_unit(second)
	check(rig.is_selection_focus_active(), "A new selection starts moving before interruption")
	rig._pan(Vector2.RIGHT, 0.016)
	check(not rig.is_selection_focus_active(), "Manual pan interrupts selection focus")

	# Automatic cycling uses the same path but does not recenter a comfortable unit.
	rig.focus_position(third.global_position)
	level.turn_manager.call("_set_active_unit", third, false)
	check(not rig.is_selection_focus_active(), "Automatic selection avoids redundant movement for an already visible unit")
	rig.global_position = level.turn_manager.enemy_units[0].global_position
	level.turn_manager.advance_automated_player(third)
	check(level.turn_manager.active_unit == first, "Automatic player cycling chooses the next available unit")
	check(rig.is_selection_focus_active(), "Automatic next-unit selection focuses an offscreen unit")
	await create_timer(0.2).timeout

	# Replay owns its camera policy; selection signals cannot override it.
	level.battle_controller.replay_mode = true
	rig.global_position = first.global_position
	level.turn_manager.call("_set_active_unit", second, true)
	check(not rig.is_selection_focus_active() and rig.global_position.is_equal_approx(first.global_position), "Replay selection does not override replay camera ownership")

	# Replay mode 1 deliberately invokes that same camera transition directly.
	# Its wait remains interruptible so replay never traps manual camera input.
	var replay_player := BattleReplayPlayer.new()
	replay_player.level = level
	replay_player.camera_mode = BattleReplayPlayer.CameraMode.SELECTION_FOCUS
	level.add_child(replay_player)
	rig.global_position = level.turn_manager.enemy_units[0].global_position
	replay_player._focus_action.call_deferred({"kind": "wait", "actor": String(second.name)})
	await process_frame
	check(rig.is_selection_focus_active(), "Replay selection-focus mode uses the shared smooth transition")
	rig._pan(Vector2.RIGHT, 0.016)
	check(not rig.is_selection_focus_active(), "Manual pan interrupts replay selection focus")
	await process_frame

	level.queue_free()
	await process_frame
	await process_frame
	print("Tactical camera selection: %d failure(s)" % failures)
	quit(1 if failures else 0)
