extends SceneTree
## The Skirmisher: fast, light, short-ranged, with a small-caliber weapon that scales every hit it deals
## (UnitStats stay untouched; TacticalUnit.weapon_damage_multiplier). A weapon multiplier of 1.0 must change
## nothing for any other unit. Covers the preview, the committed damage, a shield, and the AI's valuation.

const BATTLE_SCENE := preload("res://levels/prototype_map/prototype_map.tscn")

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _put(level: BattleLevel, unit: TacticalUnit, cell: Vector3i) -> void:
	var grid := level.battle_controller.grid_manager
	var data := grid.get_cell_data(cell)
	if data:
		data.cover_type = MapCellData.CoverType.NONE
		data.cover_height = 0.0
		data.blocks_line_of_sight = false
	grid.map_data.rebuild_los_index()
	var old := grid.get_unit_grid(unit)
	unit.global_position = grid.grid_to_world(cell) + Vector3.UP * unit.standing_height
	grid.update_unit_position(unit, old, cell)

func _rng_for_outcome(hit_chance: int, should_hit: bool) -> RandomNumberGenerator:
	for candidate_seed in range(10000):
		var candidate := RandomNumberGenerator.new()
		candidate.seed = candidate_seed
		if (candidate.randf() * 100.0 < float(hit_chance)) == should_hit:
			candidate.seed = candidate_seed
			return candidate
	return RandomNumberGenerator.new()

func _run() -> void:
	var skirmisher := TacticalArchetypeCatalog.get_definition(&"skirmisher")
	var generic := TacticalArchetypeCatalog.get_definition(&"generic")
	check(skirmisher != null and TacticalArchetypeCatalog.validate_catalog().is_empty(), "The Skirmisher is in a valid catalog")
	check(skirmisher.shield_capability == null and skirmisher.weapon_damage_multiplier < 1.0 and is_equal_approx(generic.weapon_damage_multiplier, 1.0), "It has a weaker weapon and no shield; Generic keeps full damage")
	check(skirmisher.movement_range > 5 and skirmisher.attack_range < 10 and skirmisher.marker_color.r > 0.7 and skirmisher.marker_color.g < 0.3, "It is fast, short-ranged and wears a red stripe")

	var config := BattleConfiguration.new()
	config.player_count = 2
	config.enemy_count = 3
	config.player_archetypes = [&"skirmisher", &"generic"]
	config.enemy_archetypes = [&"generic", &"bulwark", &"generic"]
	config.battle_seed = 6116
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 1, false)
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	while level.turn_manager.current_round == 0: await process_frame
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	var runner: TacticalUnit = level.turn_manager.player_units[0]
	var friend: TacticalUnit = level.turn_manager.player_units[1]
	var plain: TacticalUnit = level.turn_manager.enemy_units[0]
	var tank: TacticalUnit = level.turn_manager.enemy_units[1]
	var other: TacticalUnit = level.turn_manager.enemy_units[2]
	var service := level.battle_controller.action_service
	var grid := level.battle_controller.grid_manager
	var home := grid.get_unit_grid(runner)
	_put(level, plain, home + Vector3i.RIGHT)
	_put(level, tank, home + Vector3i.LEFT)
	_put(level, other, home + Vector3i(0, 0, 2))
	var full := CombatRules.cover_tuning.damage_for_hit(1.0)
	check(runner.stats.speed == 7 and runner.attack_range == 9 and runner.stats.max_hp == 110 and is_equal_approx(runner.weapon_damage_multiplier, 0.8) and runner.shield_capability == null, "The Skirmisher spawns with its numbers (speed %d, range %d, HP %d)" % [runner.stats.speed, runner.attack_range, runner.stats.max_hp])
	check(is_equal_approx(plain.weapon_damage_multiplier, 1.0), "Other units keep full damage")

	var out := service.query_attack(runner.tactical_id, plain.tactical_id)
	var back := service.query_attack(plain.tactical_id, runner.tactical_id)
	check(out.damage_on_hit == CombatRules.cover_tuning.damage_for_hit(0.8) and out.damage_on_hit < full, "The Skirmisher's hit is smaller in the preview (%d of %d)" % [out.damage_on_hit, full])
	check(back.damage_on_hit == full, "A Generic unit still deals full damage to it")
	check(out.expected_damage < float(full) * float(out.hit_chance) / 100.0, "Expected damage uses the weaker hit")

	level.turn_manager.current_phase = TurnManager.TurnPhase.PLAYER_TURN
	level.turn_manager.active_unit = runner
	runner.stats.set_available_ap_for_setup(2)
	runner.stats.current_supply_points = 4
	service.set("_combat_rng", _rng_for_outcome(out.hit_chance, true))
	var hp_before := plain.stats.current_hp
	var shot := await service.submit_attack(service.make_attack_request(runner, plain, TacticalActionRequest.Source.PLAYER), true)
	check(shot != null and shot.did_hit and shot.damage == out.damage_on_hit and plain.stats.current_hp == hp_before - out.damage_on_hit, "The committed hit deals exactly the previewed smaller damage")

	# Against a shield the weapon and the shield multiply.
	level.turn_manager.current_phase = TurnManager.TurnPhase.ENEMY_TURN
	level.turn_manager.active_unit = tank
	tank.stats.set_available_ap_for_setup(3)
	var stance := await service.submit_shield(service.make_shield_request(tank, runner, TacticalActionRequest.Source.AI), true)
	check(stance != null and tank.tactical_state.is_shielding, "Setup: the Bulwark is shielding")
	var through := service.query_attack(runner.tactical_id, tank.tactical_id)
	check(through.shield_applied and through.damage_on_hit == CombatRules.cover_tuning.damage_for_hit(0.8 * tank.shield_capability.damage_multiplier), "A shielded target takes the weapon times the shield (%d)" % through.damage_on_hit)

	# The AI prices a shield by what each attacker's weapon would really deal.
	tank.tactical_state.clear_shield()
	tank.stats.set_available_ap_for_setup(3)
	_put(level, friend, grid.get_unit_grid(tank) + Vector3i(0, 0, 1))
	var vs_skirmisher := AIPlanEvaluator.best_shield_plan(tank, [runner] as Array[TacticalUnit], level.battle_controller)
	var vs_generic := AIPlanEvaluator.best_shield_plan(tank, [friend] as Array[TacticalUnit], level.battle_controller)
	check(vs_skirmisher != null and vs_generic != null and vs_skirmisher.value > 0.0 and vs_skirmisher.value < vs_generic.value, "A shield is worth less against the weaker weapon (%.2f against %.2f)" % [vs_skirmisher.value if vs_skirmisher else -1.0, vs_generic.value if vs_generic else -1.0])
	level.queue_free()
	await process_frame
	await process_frame
	print("Skirmisher weapon: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
