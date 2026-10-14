extends SceneTree

const CASES := [
	{"label": "authored eliminate", "seed": 25200, "mission": MissionObjectiveDefinition.Kind.ELIMINATE, "generated": false, "size": Vector2i(32, 24), "refinery": false, "player": AICommanderPolicy.Profile.DEFAULT, "enemy": AICommanderPolicy.Profile.CAUTIOUS},
	{"label": "generated reach", "seed": 25003, "mission": MissionObjectiveDefinition.Kind.REACH, "generated": true, "size": Vector2i(24, 20), "refinery": false, "player": AICommanderPolicy.Profile.CAUTIOUS, "enemy": AICommanderPolicy.Profile.DEFAULT},
	{"label": "generated terminal", "seed": 25107, "mission": MissionObjectiveDefinition.Kind.INTERACT_TERMINAL, "generated": true, "size": Vector2i(32, 24), "refinery": false, "player": AICommanderPolicy.Profile.AGGRESSIVE, "enemy": AICommanderPolicy.Profile.DEFAULT},
	{"label": "refinery survive", "seed": 25104, "mission": MissionObjectiveDefinition.Kind.SURVIVE, "generated": true, "size": Vector2i(40, 30), "refinery": true, "player": AICommanderPolicy.Profile.DEFAULT, "enemy": AICommanderPolicy.Profile.AGGRESSIVE},
	{"label": "refinery rescue cautious", "seed": 940059876, "mission": MissionObjectiveDefinition.Kind.RESCUE, "generated": true, "size": Vector2i(40, 30), "refinery": true, "player": AICommanderPolicy.Profile.CAUTIOUS, "enemy": AICommanderPolicy.Profile.AGGRESSIVE},
	{"label": "refinery rescue aggressive", "seed": 940059876, "mission": MissionObjectiveDefinition.Kind.RESCUE, "generated": true, "size": Vector2i(40, 30), "refinery": true, "player": AICommanderPolicy.Profile.AGGRESSIVE, "enemy": AICommanderPolicy.Profile.CAUTIOUS},
]

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
	var team_profiles := {0: {}, 1: {}}
	var mission_ids := {}
	for test_case in CASES:
		var result := await simulator.run_match({
			"seed": test_case.seed,
			"mission_kind": test_case.mission,
			"player_count": 5,
			"enemy_count": 5,
			"generated_map": test_case.generated,
			"map_size": test_case.size,
			"refinery": test_case.refinery,
			"difficulty": AIDifficultyPolicy.Tier.NORMAL,
			"player_commander": test_case.player,
			"enemy_commander": test_case.enemy,
			"maximum_rounds": 30,
			"stall_seconds": 8.0,
			"timeout_seconds": 45.0,
		})
		check(result.completed(), "%s completes without stall, timeout, or round limit: %s" % [test_case.label, result.summary()])
		check(result.decision_count > 0, "%s records inspectable AI decisions" % test_case.label)
		check(result.decision_records.any(func(record: Dictionary): return record.get("action", "") in ["Move", "Attack", "Guard", "Interact", "Extract"]), "%s produces a meaningful tactical or objective action" % test_case.label)
		team_profiles[0][test_case.player] = true
		team_profiles[1][test_case.enemy] = true
		mission_ids[result.mission_id] = true
		print("[CommanderFreeze] %s — %s" % [test_case.label, result.summary()])
	for team_id in [0, 1]:
		for profile in AICommanderPolicy.Profile.size():
			check(team_profiles[team_id].has(profile), "Team %d exercises %s" % [team_id, AICommanderPolicy.get_label(profile)])
	check(mission_ids.size() >= 5, "Commander validation spans at least five mission families")
	Engine.time_scale = previous_time_scale
	simulator.queue_free()
	await process_frame
	print("Commander Foundation validation: %d failure(s)" % failures)
	quit(1 if failures else 0)
