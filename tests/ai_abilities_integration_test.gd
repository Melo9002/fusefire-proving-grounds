extends SceneTree

const BATTLE_SCENE := preload("res://levels/prototype_map/prototype_map.tscn")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	await _test_shield_policy_uses_capability()
	await _test_guard_policy_is_bounded()
	await _test_terminal_approach_and_zero_ap_interaction()
	await _test_active_reaction_casualty_advances_selection()
	print("AI abilities integration: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_shield_policy_uses_capability() -> void:
	var level := await _create_battle(&"shieldbearer", MissionObjectiveDefinition.Kind.ELIMINATE, 17110)
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var threat: TacticalUnit = level.turn_manager.enemy_units[0]
	var ai := _policy_adapter(level, actor)
	_prepare_adjacent(level, actor, threat)
	actor.stats.set_available_ap_for_setup(1)
	check(actor.shield_capability != null and ai.call("_most_relevant_defensive_threat") == threat, "Shield policy discovers a legal incoming threat through capability data")
	check(await ai.call("_try_shield_against", threat), "Shieldbearer AI submits Shield through the authoritative action path")
	check(actor.tactical_state.is_shielding and actor.stats.current_ap == 0, "AI Shield spends the final AP and commits stance state")
	ai.free()
	await _dispose(level)

func _test_guard_policy_is_bounded() -> void:
	var level := await _create_battle(&"generic", MissionObjectiveDefinition.Kind.ELIMINATE, 17111)
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var threat: TacticalUnit = level.turn_manager.enemy_units[0]
	var ai := _policy_adapter(level, actor)
	_prepare_adjacent(level, actor, threat)
	actor.stats.set_available_ap_for_setup(2)
	check(ai.call("_guard_has_plausible_trigger"), "Guard policy recognizes a plausible legal reaction target")
	check(await ai.call("_try_guard_if_useful"), "AI submits Guard through the shared authoritative query")
	check(actor.tactical_state.is_overwatching and actor.stats.current_ap == 0, "Guard ends activation while preserving its one reaction")
	actor.tactical_state.clear_overwatch()
	actor.stats.set_available_ap_for_setup(2)
	ai.set("_consecutive_low_value_actions", 1)
	check(not await ai.call("_try_guard_if_useful"), "A previous low-value defensive turn prevents repeated Guard stalling")
	ai.free()
	await _dispose(level)

func _test_terminal_approach_and_zero_ap_interaction() -> void:
	var config := BattleConfiguration.new()
	config.player_count = 1
	config.enemy_count = 1
	config.battle_seed = 17112
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.INTERACT_TERMINAL, 1, false)
	config.mission.terminals[0].grid_position = Vector3i(3, 0, 8)
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	while level.turn_manager.current_round == 0: await process_frame
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var terminal := level.objective_manager.get_terminal_state(&"main_terminal")
	var ai := _policy_adapter(level, actor)
	ai.objective_manager = level.objective_manager
	ai.set("_objective_manager", level.objective_manager)
	ai.current_mission_intent = level.objective_manager.get_mission_intent(actor)
	var squad := level.battle_controller.get_squad_context(actor)
	squad.begin_unit(actor)
	ai.set("_squad_context", squad)
	actor.stats.set_available_ap_for_setup(1)
	var result: int = await ai.call("_try_mission_step", false)
	check(result == AIController.MissionStepResult.INTERACTED, "AI approaches and interacts with its required terminal in one mission step")
	check(actor.stats.current_ap == 0 and terminal.is_activated, "Terminal remains free after AI spends its final AP moving adjacent")
	check(level.objective_manager.get_objective(&"activate_terminal").is_completed(), "AI terminal interaction commits the mission objective")
	check(level.battle_controller.action_service.state_revision == 2, "AI Move and free terminal interaction remain two ordered authoritative transactions")
	ai.free()
	await _dispose(level)

func _test_active_reaction_casualty_advances_selection() -> void:
	var config := BattleConfiguration.new()
	config.player_count = 2
	config.enemy_count = 1
	config.battle_seed = 17113
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.RESCUE, 1, false)
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	while level.turn_manager.current_round == 0: await process_frame
	var casualty: TacticalUnit = level.turn_manager.player_units[0]
	var survivor: TacticalUnit = level.turn_manager.player_units[1]
	level.turn_manager.call("_set_active_unit", casualty)
	level.turn_manager.remove_unit(casualty)
	await process_frame
	await process_frame
	check(level.turn_manager.active_unit == survivor, "Defeating the active actor during a reaction advances to a surviving unit")
	check(level.turn_manager.current_phase == TurnManager.TurnPhase.PLAYER_TURN, "Reaction defeat preserves the current phase while another actor can act")
	await _dispose(level)

func _create_battle(archetype: StringName, mission_kind: MissionObjectiveDefinition.Kind, seed: int) -> BattleLevel:
	var config := BattleConfiguration.new()
	config.player_count = 1
	config.enemy_count = 1
	config.player_archetypes = [archetype]
	config.battle_seed = seed
	config.mission = MissionCatalog.create_mission(mission_kind, 1, false)
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	while level.turn_manager.current_round == 0: await process_frame
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	return level

func _policy_adapter(level: BattleLevel, actor: TacticalUnit) -> AIController:
	var ai := AIController.new()
	ai.unit = actor
	ai.turn_manager = level.turn_manager
	ai.battle_controller = level.battle_controller
	ai.objective_manager = level.objective_manager
	ai.set("_policy", AIDifficultyPolicy.create(AIDifficultyPolicy.Tier.NORMAL))
	var decision_rng := RandomNumberGenerator.new()
	decision_rng.seed = 17117
	ai.set("_decision_rng", decision_rng)
	return ai

func _prepare_adjacent(level: BattleLevel, actor: TacticalUnit, threat: TacticalUnit) -> void:
	var grid := level.battle_controller.grid_manager
	var actor_cell := grid.get_unit_grid(actor)
	var old_threat_cell := grid.get_unit_grid(threat)
	var threat_cell := actor_cell + Vector3i.RIGHT
	var data := grid.get_cell_data(threat_cell)
	if data:
		data.cover_type = MapCellData.CoverType.NONE
		data.cover_height = 0.0
		data.blocks_line_of_sight = false
	grid.map_data.rebuild_los_index()
	threat.global_position = grid.grid_to_world(threat_cell) + Vector3.UP * threat.standing_height
	grid.update_unit_position(threat, old_threat_cell, threat_cell)

func _dispose(level: BattleLevel) -> void:
	level.queue_free()
	await process_frame
	await process_frame
