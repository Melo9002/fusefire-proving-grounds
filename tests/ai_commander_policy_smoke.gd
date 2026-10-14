extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	_check_default_composition()
	await _check_team_ownership_and_diagnostics()
	print("AI commander policy smoke: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_default_composition() -> void:
	for tier in AIDifficultyPolicy.Tier.size():
		var difficulty := AIDifficultyPolicy.create(tier as AIDifficultyPolicy.Tier)
		var commander := AICommanderPolicy.create()
		var composed := commander.compose(difficulty)
		check(commander.get_policy_id() == &"default", "Default commander has a stable policy ID")
		check(commander.get_strategic_intent() == AICommanderPolicy.StrategicIntent.BALANCED_ENGAGEMENT, "Default commander exposes balanced strategic intent")
		for property_name in _difficulty_properties():
			check(composed.get(property_name) == difficulty.get(property_name), "Default preserves %s at tier %d" % [property_name, tier])

func _check_team_ownership_and_diagnostics() -> void:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(1, 1, false, 41320, 1)
	root.add_child(level)
	await create_timer(0.2).timeout
	var battle := level.battle_controller
	var player := level.turn_manager.player_units[0]
	var ally := level.turn_manager.allied_units[0]
	var enemy := level.turn_manager.enemy_units[0]
	check(battle.get_commander_policy(player) == battle.get_commander_policy(ally), "Player and ally share one team commander policy")
	check(battle.get_commander_policy(player) != battle.get_commander_policy(enemy), "Opposing teams own distinct commander policy instances")
	var records: Array[Dictionary] = []
	battle.ai_decision_recorded.connect(func(value: Dictionary): records.append(value))
	battle.record_ai_decision(enemy, "Wait", enemy.name, "Fixture decision", "None")
	var record: Dictionary = records[0] if not records.is_empty() else {}
	check(record.get("commander_policy_id", "") == "default", "Decision diagnostics include the stable commander policy ID")
	check(record.get("strategic_intent", "") == "Balanced engagement", "Decision diagnostics include strategic intent")
	level.queue_free()
	await process_frame

func _difficulty_properties() -> Array[StringName]:
	return [
		&"tier", &"wounded_target_weight", &"finishing_bonus_weight", &"focus_penalty_weight",
		&"movement_progress_weight", &"crowding_penalty_weight", &"survival_cover_weight",
		&"survival_separation_weight", &"safe_advance_exposure_tolerance", &"position_cover_weight",
		&"position_exposure_weight", &"position_firing_weight", &"position_danger_weight",
		&"target_vip_weight", &"target_threat_weight", &"target_mission_weight", &"lapse_chance",
		&"lapse_score_margin",
	]
