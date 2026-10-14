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
	_check_cautious_composition()
	_check_aggressive_composition()
	_check_configuration_round_trip()
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

func _check_cautious_composition() -> void:
	for tier in AIDifficultyPolicy.Tier.size():
		var difficulty := AIDifficultyPolicy.create(tier as AIDifficultyPolicy.Tier)
		var commander := AICommanderPolicy.create(AICommanderPolicy.Profile.CAUTIOUS)
		var composed := commander.compose(difficulty)
		check(commander.get_policy_id() == &"cautious", "Cautious commander has a stable policy ID")
		check(is_equal_approx(composed.position_cover_weight, difficulty.position_cover_weight * 1.30), "Cautious composes cover once")
		check(is_equal_approx(composed.position_exposure_weight, difficulty.position_exposure_weight * 1.30), "Cautious composes exposure once")
		check(is_equal_approx(composed.position_danger_weight, difficulty.position_danger_weight * 1.35), "Cautious composes crossfire danger once")
		check(is_equal_approx(composed.position_firing_weight, difficulty.position_firing_weight * 0.90), "Cautious modestly reduces firing-position emphasis")
		check(is_equal_approx(composed.movement_progress_weight, difficulty.movement_progress_weight * 0.95), "Cautious preserves most movement progress value")
		check(is_equal_approx(composed.crowding_penalty_weight, difficulty.crowding_penalty_weight * 1.15), "Cautious strengthens squad spacing")
		check(is_equal_approx(composed.safe_advance_exposure_tolerance, maxf(0.0, difficulty.safe_advance_exposure_tolerance - 0.10)), "Cautious threshold delta clamps at zero")
		check(composed.lapse_chance == difficulty.lapse_chance and composed.lapse_score_margin == difficulty.lapse_score_margin, "Commander leaves difficulty lapse semantics unchanged")
		check(composed.survival_cover_weight == difficulty.survival_cover_weight, "Cautious does not activate the inactive survival cover field")

func _check_configuration_round_trip() -> void:
	var config := BattleConfiguration.new()
	config.player_commander = AICommanderPolicy.Profile.CAUTIOUS
	config.enemy_commander = AICommanderPolicy.Profile.AGGRESSIVE
	var rebuilt := BattleConfiguration.new()
	rebuilt.apply_replay(config.to_replay())
	check(rebuilt.player_commander == AICommanderPolicy.Profile.CAUTIOUS, "Player-team commander survives replay configuration")
	check(rebuilt.enemy_commander == AICommanderPolicy.Profile.AGGRESSIVE, "Enemy-team commander survives replay configuration")
	var historical := BattleConfiguration.new()
	historical.apply_replay({})
	check(historical.player_commander == AICommanderPolicy.Profile.DEFAULT and historical.enemy_commander == AICommanderPolicy.Profile.DEFAULT, "Historical configurations default both teams safely")

func _check_aggressive_composition() -> void:
	for tier in AIDifficultyPolicy.Tier.size():
		var difficulty := AIDifficultyPolicy.create(tier as AIDifficultyPolicy.Tier)
		var commander := AICommanderPolicy.create(AICommanderPolicy.Profile.AGGRESSIVE)
		var composed := commander.compose(difficulty)
		check(commander.get_policy_id() == &"aggressive", "Aggressive commander has a stable policy ID")
		check(is_equal_approx(composed.movement_progress_weight, difficulty.movement_progress_weight * 1.20), "Aggressive composes progress once")
		check(is_equal_approx(composed.position_firing_weight, difficulty.position_firing_weight * 1.20), "Aggressive composes firing opportunity once")
		check(is_equal_approx(composed.wounded_target_weight, difficulty.wounded_target_weight * 1.15), "Aggressive composes target vulnerability once")
		check(is_equal_approx(composed.finishing_bonus_weight, difficulty.finishing_bonus_weight * 1.25), "Aggressive composes finishing value once")
		check(is_equal_approx(composed.target_threat_weight, difficulty.target_threat_weight * 1.10), "Aggressive composes target threat once")
		check(is_equal_approx(composed.position_cover_weight, difficulty.position_cover_weight * 0.90), "Aggressive retains reduced cover value")
		check(is_equal_approx(composed.position_exposure_weight, difficulty.position_exposure_weight * 0.85), "Aggressive retains meaningful exposure penalties")
		check(is_equal_approx(composed.position_danger_weight, difficulty.position_danger_weight * 0.90), "Aggressive retains meaningful danger penalties")
		check(is_equal_approx(composed.safe_advance_exposure_tolerance, difficulty.safe_advance_exposure_tolerance + 0.15), "Aggressive permits a modest extra exposure increase")
		check(composed.lapse_chance == difficulty.lapse_chance and composed.lapse_score_margin == difficulty.lapse_score_margin, "Aggressive leaves difficulty lapse semantics unchanged")
		check(composed.survival_cover_weight == difficulty.survival_cover_weight, "Aggressive does not activate the inactive survival cover field")

func _check_team_ownership_and_diagnostics() -> void:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	var config := BattleConfiguration.new()
	config.player_count = 1
	config.enemy_count = 1
	config.ally_count = 1
	config.battle_seed = 41320
	config.player_commander = AICommanderPolicy.Profile.CAUTIOUS
	config.enemy_commander = AICommanderPolicy.Profile.DEFAULT
	level.configure_battle(config)
	root.add_child(level)
	await create_timer(0.2).timeout
	var battle := level.battle_controller
	var player := level.turn_manager.player_units[0]
	var ally := level.turn_manager.allied_units[0]
	var enemy := level.turn_manager.enemy_units[0]
	check(battle.get_commander_policy(player) == battle.get_commander_policy(ally), "Player and ally share one team commander policy")
	check(battle.get_commander_policy(player) != battle.get_commander_policy(enemy), "Opposing teams own distinct commander policy instances")
	check(battle.get_commander_policy(player).profile == AICommanderPolicy.Profile.CAUTIOUS, "Player team receives configured Cautious doctrine")
	check(battle.get_commander_policy(enemy).profile == AICommanderPolicy.Profile.DEFAULT, "Enemy team independently retains Default doctrine")
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
