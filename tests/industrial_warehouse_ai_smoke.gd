extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 16.0
	var simulator := AIMatchSimulator.new()
	root.add_child(simulator)
	var result := await simulator.run_match({
		"seed": 940059876,
		"mission_kind": MissionObjectiveDefinition.Kind.REACH,
		"player_count": 3,
		"enemy_count": 3,
		"map_size": Vector2i(40, 30),
		"industrial_warehouse": true,
		"difficulty": AIDifficultyPolicy.Tier.NORMAL,
		"maximum_rounds": 12,
		"stall_seconds": 6.0,
		"timeout_seconds": 35.0,
	})
	var passed := result.map_source == IndustrialWarehouseLayoutBuilder.SOURCE_KIND \
		and result.validation_errors.is_empty() \
		and result.decision_count > 0 \
		and result.status == AIMatchSimulationResult.Status.COMPLETED
	var recording = BattleReplaySession.last_recording
	passed = passed and recording != null
	if recording:
		var replay := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
		replay.configure_replay(recording)
		root.add_child(replay)
		while replay.turn_manager.current_round == 0:
			await process_frame
		var player := replay.get_node("BattleReplayPlayer") as BattleReplayPlayer
		player.set_playback_speed(4.0)
		var deadline := Time.get_ticks_msec() + 30000
		while not player.playback_complete and Time.get_ticks_msec() < deadline:
			await process_frame
		passed = passed and player.playback_succeeded and player.verified_actions == recording.actions.size()
		print("Industrial playback: %d/%d actions, succeeded=%s" % [player.verified_actions, recording.actions.size(), player.playback_succeeded])
		replay.queue_free()
		await process_frame
	Engine.time_scale = previous_time_scale
	print("Industrial warehouse AI: %s — %s" % ["PASSED" if passed else "FAILED", result.summary()])
	if not passed:
		push_error("Industrial AI integration failed: %s" % result.summary())
	quit(0 if passed else 1)
