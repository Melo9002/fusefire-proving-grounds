extends SceneTree
## The Bulwark: an omnidirectional shield arm with a limited capacity, slow and short-ranged, marked by a
## class stripe. Covers the archetype's numbers, the capacity rule (rules, replayed state, AI valuation)
## and that a shield without a limit behaves exactly as before.

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

func _run() -> void:
	_archetype_and_capability()
	await _capacity_in_battle()
	await _marker()
	print("Bulwark shield: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _archetype_and_capability() -> void:
	var bulwark := TacticalArchetypeCatalog.get_definition(&"bulwark")
	var generic := TacticalArchetypeCatalog.get_definition(&"generic")
	check(bulwark != null and TacticalArchetypeCatalog.validate_catalog().is_empty(), "The Bulwark is in a valid catalog")
	var capability := bulwark.shield_capability
	check(capability != null and is_equal_approx(capability.protected_arc_degrees, 360.0), "The Bulwark's shield covers every direction")
	check(capability.max_attacks_covered == 2 and capability.accuracy_modifier < 0 and capability.damage_multiplier < 1.0, "It is harder to hit and limited to two covered attacks")
	check(bulwark.movement_range > 0 and bulwark.attack_range > 0 and bulwark.attack_range < 10, "It has its own, shorter reach than the battle default of 10")
	check(bulwark.marker_color.a > 0.0 and generic.marker_color.a == 0.0, "Only the Bulwark carries a stripe")
	# A shield without a limit keeps its original recorded identity.
	var physical: ShieldCapability = load("res://units/capabilities/physical_shield.tres")
	var original := "shield-1:" + JSON.stringify([physical.stance_ap_cost, physical.protected_arc_degrees, physical.damage_multiplier, physical.accuracy_modifier, physical.attacks_allowed, physical.reload_allowed], "", true, true).sha256_text()
	check(physical.max_attacks_covered == 0 and physical.signature() == original, "The original Shield keeps its signature")
	var limited := physical.duplicate() as ShieldCapability
	limited.max_attacks_covered = 3
	check(limited.signature() != physical.signature() and bulwark.shield_capability.signature() != physical.signature(), "A capacity changes the signature")
	check(physical.has_capacity(99) and capability.has_capacity(1) and not capability.has_capacity(2), "Capacity 0 is unlimited; a limit is used up")

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

func _capacity_in_battle() -> void:
	var config := BattleConfiguration.new()
	config.player_count = 1
	config.enemy_count = 3
	config.player_archetypes = [&"bulwark"]
	config.enemy_archetypes = [&"generic", &"generic", &"generic"]
	config.battle_seed = 6115
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 1, false)
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	while level.turn_manager.current_round == 0: await process_frame
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var east: TacticalUnit = level.turn_manager.enemy_units[0]
	var west: TacticalUnit = level.turn_manager.enemy_units[1]
	var north: TacticalUnit = level.turn_manager.enemy_units[2]
	var service := level.battle_controller.action_service
	var grid := level.battle_controller.grid_manager
	var home := grid.get_unit_grid(actor)
	_put(level, east, home + Vector3i.RIGHT)
	_put(level, west, home + Vector3i.LEFT)
	_put(level, north, home + Vector3i(0, 0, -2))
	check(actor.stats.speed == 4 and actor.attack_range == 8 and actor.stats.max_hp == 110 and actor.archetype_id == &"bulwark", "The Bulwark spawns tougher, slower and shorter-ranged than the baseline (speed %d, range %d, HP %d)" % [actor.stats.speed, actor.attack_range, actor.stats.max_hp])

	var open_chance := service.query_attack(west.tactical_id, actor.tactical_id).hit_chance
	var stance := await service.submit_shield(service.make_shield_request(actor, east, TacticalActionRequest.Source.PLAYER), true)
	check(stance != null and actor.tactical_state.is_shielding and actor.tactical_state.shield_attacks_covered == 0, "The stance starts with nothing covered")

	# Omnidirectional: the shield faces east and still covers an attacker standing west and one north.
	var from_west := service.query_attack(west.tactical_id, actor.tactical_id)
	var from_north := service.query_attack(north.tactical_id, actor.tactical_id)
	check(from_west.shield_applied and from_north.shield_applied, "The shield covers attackers from behind and from the side")
	check(from_west.hit_chance < open_chance, "Covered attacks are harder to hit (%d before, %d after)" % [open_chance, from_west.hit_chance])
	check(from_west.damage_on_hit < CombatRules.cover_tuning.damage_for_hit(1.0), "Covered hits do less damage")

	level.turn_manager.current_phase = TurnManager.TurnPhase.ENEMY_TURN
	var covered_damage := from_west.damage_on_hit
	var attackers: Array[TacticalUnit] = [east, west, north]
	for index in 2:
		var attacker := attackers[index]
		level.turn_manager.active_unit = attacker
		attacker.stats.set_available_ap_for_setup(2)
		attacker.stats.current_supply_points = 4
		var query := service.query_attack(attacker.tactical_id, actor.tactical_id)
		service.set("_combat_rng", _rng_for_outcome(query.hit_chance, true))
		var hp_before := actor.stats.current_hp
		var shot := await service.submit_attack(service.make_attack_request(attacker, actor, TacticalActionRequest.Source.AI), true)
		check(shot != null and shot.shield_applied and shot.did_hit and actor.stats.current_hp == hp_before - covered_damage, "Attack %d is covered and does the reduced damage" % [index + 1])
		check(actor.tactical_state.shield_attacks_covered == index + 1, "The shield counts attack %d" % [index + 1])

	# The third attack finds the arm overwhelmed.
	level.turn_manager.active_unit = north
	north.stats.set_available_ap_for_setup(2)
	north.stats.current_supply_points = 4
	var third := service.query_attack(north.tactical_id, actor.tactical_id)
	check(not third.shield_applied and third.damage_on_hit == CombatRules.cover_tuning.damage_for_hit(1.0), "After two covered attacks the third gets no protection")
	check(third.hit_chance > from_north.hit_chance and third.evaluation.shield_reason.contains("overwhelmed"), "The unshielded chance is higher and the reason says why (%s)" % third.evaluation.shield_reason)
	service.set("_combat_rng", _rng_for_outcome(third.hit_chance, true))
	var hp_before_third := actor.stats.current_hp
	var shot_three := await service.submit_attack(service.make_attack_request(north, actor, TacticalActionRequest.Source.AI), true)
	check(shot_three != null and not shot_three.shield_applied and actor.stats.current_hp == hp_before_third - CombatRules.cover_tuning.damage_for_hit(1.0), "The third hit lands at full damage")
	check(actor.tactical_state.shield_attacks_covered == 2, "An uncovered attack is not counted")

	# The count is replayed state and ends with the stance.
	var fingerprint := BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager)
	check(fingerprint.contains("shield_covered=%s,2" % actor.tactical_id), "The fingerprint carries the count")
	actor.tactical_state.begin_activation(level.turn_manager.current_round + 1, int(level.turn_manager.current_phase))
	check(not actor.tactical_state.is_shielding and actor.tactical_state.shield_attacks_covered == 0, "The stance and its count end at the next activation")
	check(not BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager).contains("shield_covered="), "No stance, no count in the fingerprint")

	# AI valuation honours the capacity.
	var hostiles: Array[TacticalUnit] = [east, west, north]
	level.turn_manager.current_phase = TurnManager.TurnPhase.PLAYER_TURN
	actor.stats.set_available_ap_for_setup(3)
	var unlimited := actor.shield_capability.duplicate() as ShieldCapability
	unlimited.max_attacks_covered = 0
	actor.shield_capability = unlimited
	var all_three := AIPlanEvaluator.best_shield_plan(actor, hostiles, level.battle_controller)
	var one := unlimited.duplicate() as ShieldCapability
	one.max_attacks_covered = 1
	actor.shield_capability = one
	var plan_one := AIPlanEvaluator.best_shield_plan(actor, hostiles, level.battle_controller)
	var two := unlimited.duplicate() as ShieldCapability
	two.max_attacks_covered = 2
	actor.shield_capability = two
	var plan_two := AIPlanEvaluator.best_shield_plan(actor, hostiles, level.battle_controller)
	check(all_three != null and plan_one != null and plan_two != null, "Setup: the stance has a plan")
	if all_three and plan_one and plan_two:
		check(all_three.summary.contains("3 of 3") and plan_one.summary.contains("1 of 3") and plan_two.summary.contains("2 of 3"), "An all-round shield covers every attacker, a limited one only its capacity (%s | %s | %s)" % [all_three.summary, plan_one.summary, plan_two.summary])
		check(all_three.value > plan_two.value and plan_two.value > plan_one.value and plan_one.value > 0.0, "More covered attacks are worth more, in order")
	level.queue_free()
	await process_frame
	await process_frame

func _marker() -> void:
	var rig := load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate() as TacticalCharacterAdapter
	root.add_child(rig)
	for i in 4: await process_frame
	check(rig.rig.skeleton.get_node_or_null(TacticalCharacterAdapter.CLASS_MARKER_NAME) == null, "A unit with no class color has no stripe")
	rig.set_class_marker(Color(1.0, 0.82, 0.1))
	var stripe := rig.rig.skeleton.get_node_or_null(TacticalCharacterAdapter.CLASS_MARKER_NAME)
	check(stripe != null and stripe.get_child_count() == 1 and stripe.get_child(0) is MeshInstance3D, "A class color paints one stripe on the chest")
	for i in 3: await process_frame
	if stripe:
		var band := stripe.get_child(0) as MeshInstance3D
		var material := band.material_override as StandardMaterial3D
		check(material != null and material.albedo_color.is_equal_approx(Color(1.0, 0.82, 0.1)), "The stripe is yellow")
		for i in 3: await process_frame
		var world_height := band.global_basis.get_scale().y * (band.mesh as CylinderMesh).height
		check(world_height > 0.03 and world_height < 0.15, "The stripe is about 7 cm tall in the world (%.3f m)" % world_height)
	rig.set_class_marker(Color(0, 0, 0, 0))
	for i in 3: await process_frame
	check(rig.rig.skeleton.get_node_or_null(TacticalCharacterAdapter.CLASS_MARKER_NAME) == null, "A transparent color removes the stripe")
	rig.queue_free()
	await process_frame
