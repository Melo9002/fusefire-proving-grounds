extends SceneTree
## Full tactical/replay proof for the bounded Loading Yard foundation map.

const Catalog = preload("res://systems/generation/battlefield_catalog.gd")
const LoadingYard = preload("res://systems/generation/loading_yard_layout.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 16.0
	var simulator := AIMatchSimulator.new()
	root.add_child(simulator)
	var result := await simulator.run_match({
		"seed": 17,
		"mission_kind": MissionObjectiveDefinition.Kind.REACH,
		"player_count": 3,
		"enemy_count": 3,
		"map_size": Vector2i(40, 48),
		"battlefield_id": Catalog.LOADING_YARD,
		"difficulty": AIDifficultyPolicy.Tier.NORMAL,
		"maximum_rounds": 20,
		"stall_seconds": 6.0,
		"timeout_seconds": 45.0,
	})
	var passed := result.map_source == LoadingYard.SOURCE_KIND \
		and result.validation_errors.is_empty() \
		and result.decision_count > 0 \
		and result.status == AIMatchSimulationResult.Status.COMPLETED
	var recording = BattleReplaySession.last_recording
	passed = passed and recording != null and StringName(recording.configuration.get("battlefield_id", "")) == Catalog.LOADING_YARD
	if recording:
		var replay := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
		replay.configure_replay(recording)
		root.add_child(replay)
		while replay.turn_manager.current_round == 0: await process_frame
		var player := replay.get_node("BattleReplayPlayer") as BattleReplayPlayer
		player.set_playback_speed(4.0)
		var deadline := Time.get_ticks_msec() + 30000
		while not player.playback_complete and Time.get_ticks_msec() < deadline: await process_frame
		passed = passed and player.playback_succeeded and player.verified_actions == recording.actions.size()
		print("Loading Yard playback: %d/%d actions, succeeded=%s" % [player.verified_actions, recording.actions.size(), player.playback_succeeded])
		replay.queue_free()
		await process_frame
	Engine.time_scale = previous_time_scale
	print("Loading Yard AI: %s — %s" % ["PASSED" if passed else "FAILED", result.summary()])
	if not passed: push_error("Loading Yard tactical proof failed: %s" % result.summary())
	quit(0 if passed else 1)
