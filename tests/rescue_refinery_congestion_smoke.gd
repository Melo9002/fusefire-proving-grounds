extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 16.0
	var simulator := AIMatchSimulator.new()
	root.add_child(simulator)
	var result := await simulator.run_match({
		"seed": 733578405,
		"mission_kind": MissionObjectiveDefinition.Kind.RESCUE,
		"player_count": 5,
		"ally_count": 5,
		"enemy_count": 5,
		"map_size": Vector2i(40, 30),
		"refinery": true,
		"difficulty": AIDifficultyPolicy.Tier.NORMAL,
		"maximum_rounds": 30,
		"stall_seconds": 8.0,
		"timeout_seconds": 60.0,
	})
	Engine.time_scale = previous_time_scale
	var waits := result.decision_records.filter(func(record: Dictionary): return record.get("action", "") == "Wait")
	var defends := result.decision_records.filter(func(record: Dictionary): return record.get("action", "") == "Defend")
	check(result.status == AIMatchSimulationResult.Status.COMPLETED, "Crowded rescue seed reaches a battle result without stalling")
	check(defends.is_empty(), "Current AI never selects the retired Defend action")
	check(waits.all(func(record: Dictionary): return not String(record.get("reason", "")).is_empty()), "Every AI wait records a concrete reason")
	print("Rescue refinery congestion: %d failure(s), %d waits, %d decisions" % [failures, waits.size(), result.decision_count])
	simulator.queue_free()
	await process_frame
	quit(1 if failures else 0)
