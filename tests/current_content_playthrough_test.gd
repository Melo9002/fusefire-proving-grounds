extends SceneTree
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	Engine.time_scale = 12
	for id in BattlefieldCatalog.PLAYABLE:
		for seed_value in [16, 17]:
			await _case(id, seed_value)
	Engine.time_scale = 1
	print("Current content playthrough: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _case(id: StringName, seed_value: int) -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(id)
	config.battle_seed = seed_value
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 2)
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	check(level.battle_initialization_succeeded, "%s starts a valid match" % id)
	if not level.battle_initialization_succeeded:
		level.queue_free()
		await process_frame
		return
	level.battle_controller.set_debug_player_ai(true)
	var deadline := Time.get_ticks_msec() + 30000
	while level.turn_manager.battle_result == TurnManager.BattleResult.ONGOING and Time.get_ticks_msec() < deadline:
		await process_frame
	level.battle_controller.set_debug_player_ai(false)
	await process_frame
	var recording: BattleReplayRecording = level._replay_recorder.recording
	var completed := level.turn_manager.battle_result != TurnManager.BattleResult.ONGOING
	check(completed and recording.is_playable(), "%s seed %d reaches a recorded result within the bounded playthrough" % [id, seed_value])
	check(recording.actions.any(func(action): return action.kind == "move") and recording.actions.any(func(action): return action.kind == "attack"), "%s exercises real movement and shooting" % id)
	var expected_combat_log := level.battle_controller.combat_log.duplicate()
	var manifest := level.active_generated_map.content_manifest.duplicate(true)
	var path := "res://.godot/%s-%d-%d-content-test.replay.json" % [id, seed_value, OS.get_process_id()]
	check(recording.save_json(path) == OK, "Save the complete new-site recording")
	var loaded := BattleReplayRecording.load_json(path)
	check(loaded.is_playable() and loaded.configuration.content_manifest == manifest, "The saved file retains exact site and population choices")
	print("[ContentPlaythrough] %s seed %d: %d actions, round %d, %s" % [id, seed_value, loaded.actions.size(), level.turn_manager.current_round, TurnManager.BattleResult.keys()[loaded.expected_result]])
	level.queue_free()
	await process_frame
	await process_frame
	if loaded.is_playable():
		var replay := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
		replay.configure_replay(loaded)
		root.add_child(replay)
		check(replay.battle_initialization_succeeded, "Saved new-site content reconstructs before replay")
		if replay.battle_initialization_succeeded:
			var player := replay.get_node("BattleReplayPlayer") as BattleReplayPlayer
			player.set_playback_speed(4)
			deadline = Time.get_ticks_msec() + 30000
			while not player.playback_complete and Time.get_ticks_msec() < deadline:
				await process_frame
			check(player.playback_complete and player.playback_succeeded and player.verified_actions == loaded.actions.size(), "%s verifies every saved action: %s" % [id, player.last_divergence])
			check(replay.turn_manager.battle_result == loaded.expected_result and completed, "%s replay reaches the same completed result" % id)
			check(replay.battle_controller.combat_log == expected_combat_log, "%s replay regenerates the same recent combat and defensive-action explanations" % id)
		replay.queue_free()
		await process_frame
		await process_frame
	DirAccess.remove_absolute(path)
