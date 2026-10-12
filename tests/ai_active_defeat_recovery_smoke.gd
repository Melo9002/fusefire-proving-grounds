extends SceneTree

const REPORTED_STALL_SEED := 726367275

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 16.0
	var simulator := AIMatchSimulator.new()
	root.add_child(simulator)
	var result := await simulator.run_match({
		"seed": REPORTED_STALL_SEED,
		"mission_kind": MissionObjectiveDefinition.Kind.ELIMINATE,
		"player_count": 5,
		"enemy_count": 5,
		"map_size": Vector2i(40, 30),
		"refinery": true,
		"difficulty": AIDifficultyPolicy.Tier.NORMAL,
		"maximum_rounds": 30,
		"stall_seconds": 6.0,
		"timeout_seconds": 40.0,
	})
	Engine.time_scale = previous_time_scale
	var passed := result.completed()
	print("AI active-defeat recovery: %s — %s" % ["PASSED" if passed else "FAILED", result.summary()])
	if not passed:
		push_error("Reported active-unit defeat seed stalled: %s" % result.summary())
	quit(0 if passed else 1)
