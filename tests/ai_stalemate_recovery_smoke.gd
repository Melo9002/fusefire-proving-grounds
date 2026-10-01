extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 16.0
	var simulator := AIMatchSimulator.new()
	root.add_child(simulator)
	var result := await simulator.run_match({
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
	Engine.time_scale = previous_time_scale
	var passed := result.completed()
	print("AI stalemate recovery: %s — %s" % ["PASSED" if passed else "FAILED", result.summary()])
	if not passed:
		push_error("Known extraction stalemate did not recover: %s" % result.summary())
	quit(0 if passed else 1)
