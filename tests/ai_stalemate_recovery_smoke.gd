extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 16.0
	var simulator := AIMatchSimulator.new()
	root.add_child(simulator)
	var extraction_result := await simulator.run_match({
		"seed": 25005,
		"mission_kind": MissionObjectiveDefinition.Kind.EXTRACT,
		"player_count": 5,
		"ally_count": 0,
		"enemy_count": 5,
		"map_size": Vector2i(40, 30),
		"refinery": false,
		"difficulty": AIDifficultyPolicy.Tier.NORMAL,
		"maximum_rounds": 30,
		"stall_seconds": 6.0,
		"timeout_seconds": 35.0,
	})
	var eliminate_result := await simulator.run_match({
		"seed": 25100,
		"mission_kind": MissionObjectiveDefinition.Kind.ELIMINATE,
		"player_count": 5,
		"ally_count": 0,
		"enemy_count": 5,
		"map_size": Vector2i(40, 30),
		"refinery": true,
		"difficulty": AIDifficultyPolicy.Tier.NORMAL,
		"maximum_rounds": 31,
		"stall_seconds": 6.0,
		"timeout_seconds": 35.0,
	})
	Engine.time_scale = previous_time_scale
	var passed := extraction_result.completed() and eliminate_result.completed()
	print("AI extraction stalemate recovery: %s — %s" % ["PASSED" if extraction_result.completed() else "FAILED", extraction_result.summary()])
	print("AI eliminate route-detour recovery: %s — %s" % ["PASSED" if eliminate_result.completed() else "FAILED", eliminate_result.summary()])
	if not passed:
		push_error("Known stalemate did not recover: extraction=%s; eliminate=%s" % [extraction_result.summary(), eliminate_result.summary()])
	quit(0 if passed else 1)
