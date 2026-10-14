extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var easy := AIDifficultyPolicy.create(AIDifficultyPolicy.Tier.EASY)
	var normal := AIDifficultyPolicy.create(AIDifficultyPolicy.Tier.NORMAL)
	var hard := AIDifficultyPolicy.create(AIDifficultyPolicy.Tier.HARD)
	check(easy.score_target(80, 20, -30.0) < normal.score_target(80, 20, -30.0), "Easy gives wounded targets less priority than Normal")
	check(hard.score_target(80, 20, -30.0) > normal.score_target(80, 20, -30.0), "Hard gives finishers more priority than Normal")
	check(easy.permits_advance(1.0, 1.25) and not normal.permits_advance(1.0, 1.25), "Easy tolerates a modest exposure increase")
	check(normal.score_path_progress(5, -12.0) == -7.0, "Normal retains the existing movement score")
	check(hard.survival_cover_weight > normal.survival_cover_weight and easy.survival_cover_weight < normal.survival_cover_weight, "Survival cover preference scales with difficulty")

	var setup := load("res://ui/match_setup.tscn").instantiate() as MatchSetup
	root.add_child(setup)
	await process_frame
	check(setup.difficulty_option.item_count == 3, "Match setup offers all three AI difficulties")
	check(setup.difficulty_option.selected == AIDifficultyPolicy.Tier.NORMAL, "Normal is the default AI difficulty")
	check(setup.player_commander_option.item_count == 3 and setup.enemy_commander_option.item_count == 3, "Match setup offers all three commander doctrines to both teams")
	check(setup.player_commander_option.selected == AICommanderPolicy.Profile.DEFAULT and setup.enemy_commander_option.selected == AICommanderPolicy.Profile.DEFAULT, "Both teams default to the compatibility doctrine")
	var setup_panel := setup.get_node("CenterContainer/Panel") as PanelContainer
	check(setup_panel.global_position.y >= 0.0 and setup_panel.global_position.y + setup_panel.size.y <= setup.size.y, "Difficulty selector fits within the 720p setup viewport")
	setup.difficulty_option.select(AIDifficultyPolicy.Tier.HARD)
	setup.player_commander_option.select(AICommanderPolicy.Profile.CAUTIOUS)
	setup.enemy_commander_option.select(AICommanderPolicy.Profile.AGGRESSIVE)
	setup._start_battle()
	await create_timer(0.2).timeout
	var battle := current_scene as BattleLevel
	check(battle != null, "Match setup starts the configured battle")
	if battle:
		check(battle.ai_difficulty == AIDifficultyPolicy.Tier.HARD and battle.battle_controller.ai_difficulty == AIDifficultyPolicy.Tier.HARD, "Selected difficulty reaches battle systems")
		check(battle.battle_controller.get_commander_policy(battle.turn_manager.player_units[0]).profile == AICommanderPolicy.Profile.CAUTIOUS, "Selected player-team commander reaches battle systems")
		check(battle.battle_controller.get_commander_policy(battle.turn_manager.enemy_units[0]).profile == AICommanderPolicy.Profile.AGGRESSIVE, "Selected enemy commander reaches battle systems")
		var enemy_ai := battle.enemy_units_parent.get_node("EnemyUnit1AI") as AIController
		check(enemy_ai._policy.tier == AIDifficultyPolicy.Tier.HARD, "Enemy AI receives the selected policy")
		battle.queue_free()
	await process_frame
	print("AI difficulty policy smoke: %d failure(s)" % failures)
	quit(1 if failures else 0)
