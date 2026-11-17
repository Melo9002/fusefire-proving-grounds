extends SceneTree
const BattleScene := preload("res://levels/prototype_map/prototype_map.tscn")
## Step-7 contract: probability changes outcomes, never successful-hit damage.
var failures := 0
var checks := 0
var level: BattleLevel
var grid: GridManager
var actor: TacticalUnit
var target: TacticalUnit

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _prepare(distance: float, height := 0.0) -> void:
	grid.map_data = TacticalMapBuilder.generate(32, 32, 1.0, 17)
	grid.occupancy_map.clear()
	var source := Vector3i(5, 0, 5)
	var horizontal := sqrt(distance * distance - height * height)
	var destination := source + Vector3i(roundi(horizontal), 0, 0)
	grid.get_cell_data(source).world_position.y = height
	grid.get_cell_data(destination).world_position.x = grid.grid_to_world(source).x + horizontal
	for unit in [actor, target]:
		unit.attack_range = 10
		unit.tactical_state.reset()
		unit.stats.set_available_ap_for_setup(3)
		unit.stats.current_supply_points = 4
	var old_actor := actor.grid_position
	var old_target := target.grid_position
	grid.update_unit_position(actor, old_actor, source)
	grid.update_unit_position(target, old_target, destination)
	actor.global_position = grid.grid_to_world(source) + Vector3.UP * actor.standing_height
	target.global_position = grid.grid_to_world(destination) + Vector3.UP * target.standing_height

func _rng(chance: int, hit: bool, second_chance := -1) -> RandomNumberGenerator:
	for seed_value in 10000:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		if AttackActionResult.roll_hits(rng.randf() * 100.0, chance) != hit: continue
		if second_chance >= 0 and not AttackActionResult.roll_hits(rng.randf() * 100.0, second_chance): continue
		rng.seed = seed_value
		return rng
	check(false, "A deterministic seed exists for the requested outcome")
	return RandomNumberGenerator.new()

func _capture_preview() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "capture" or DisplayServer.get_name() == "headless": return
	root.size = Vector2i(1440, 900)
	for pair in [[actor, Vector3i(1, 0, 16)], [target, Vector3i(1, 0, 26)]]:
		var unit: TacticalUnit = pair[0]
		grid.update_unit_position(unit, unit.grid_position, pair[1])
		unit.global_position = grid.grid_to_world(pair[1]) + Vector3.UP * unit.standing_height
	actor.attack_range = 10
	actor.tactical_state.establish_aim()
	var rig := level.get_node("CameraRig") as TacticalCamera
	rig.set_process(false)
	rig._cancel_selection_focus()
	rig.camera.global_position = (actor.global_position + target.global_position) * 0.5 + Vector3(10, 15, 13)
	rig.camera.look_at((actor.global_position + target.global_position) * 0.5)
	var battle := level.battle_controller
	battle.set_process(false)
	var query := battle.query_attack(actor, target)
	check(query.is_legal() and query.hit_chance == 65 and query.damage_on_hit == 25, "Rendered real range previews max-range Aim at 65% and 25 damage")
	battle._set_tactical_preview(TacticalFeedbackText.shot(query))
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(args[1])
	check(root.get_texture().get_image().save_png(args[1].path_join("accuracy-damage-preview.png")) == OK, "Saved real battle UI for visual review")

func _run() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.TACTICAL_TEST_RANGE)
	config.player_count = 1
	config.enemy_count = 1
	config.content_manifest = {"population_enabled": false}
	level = BattleScene.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	check(level.battle_initialization_succeeded, "Current range initializes")
	if not level.battle_initialization_succeeded:
		level.free()
		quit(1)
		return
	grid = level.battle_controller.grid_manager
	actor = level.turn_manager.player_units[0]
	target = level.turn_manager.enemy_units[0]
	await _capture_preview()
	target.stats.max_hp = 1000
	target.stats.current_hp = 1000
	var service := level.battle_controller.action_service
	for sample in [[5.0, 0.0, false, 100], [8.0, 0.0, false, 83], [10.0, 0.0, false, 30], [10.0, 0.0, true, 65], [10.0, 2.0, true, 75]]:
		_prepare(sample[0], sample[1])
		if sample[2]:
			var aim := await service.submit_aim(service.make_aim_request(actor, TacticalActionRequest.Source.PLAYER), true)
			check(aim != null and aim.accuracy_bonus == 35, "Aim commits the editable +35 bonus")
		var query := service.query_attack(actor.tactical_id, target.tactical_id)
		check(query.is_legal() and query.hit_chance == sample[3] and query.damage_on_hit == 25, "Chance %s%% retains 25 on hit (actual %s%%)" % [sample[3], query.hit_chance])
		var rng_before := service.get_combat_rng_state()
		var state_before := BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager)
		for repeat in 20:
			service.query_attack(actor.tactical_id, target.tactical_id)
			CombatRules.evaluate_attack_from_cell(actor, actor.grid_position, target, grid, null)
			CombatRules.evaluate_attack_at_cell(actor, target, target.grid_position, grid, null, CombatRules.cover_tuning.guard_accuracy_modifier)
		check(service.get_combat_rng_state() == rng_before and state_before == BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager), "Repeated shot/destination/Guard predictions consume no RNG or state")
		service._combat_rng = _rng(query.hit_chance, true)
		var hp_before := target.stats.current_hp
		var result := await service.submit_attack(service.make_attack_request(actor, target, TacticalActionRequest.Source.PLAYER), true)
		check(result != null and result.did_hit and result.hit_chance == query.hit_chance and result.damage == 25 and target.stats.current_hp == hp_before - 25, "Successful shot applies the advertised fixed damage")
		check(result.compare_resolved(JSON.parse_string(JSON.stringify(result.resolved_dictionary()))).is_empty(), "Resolved shot evidence survives JSON normalization")
	_prepare(10)
	var query := service.query_attack(actor.tactical_id, target.tactical_id)
	service._combat_rng = _rng(query.hit_chance, false)
	var hp_before := target.stats.current_hp
	var miss := await service.submit_attack(service.make_attack_request(actor, target, TacticalActionRequest.Source.PLAYER), true)
	check(miss != null and not miss.did_hit and miss.damage == 0 and target.stats.current_hp == hp_before, "A miss applies zero damage")
	check(not AttackActionResult.roll_hits(65.0, 65) and AttackActionResult.roll_hits(64.999, 65) and AttackActionResult.roll_hits(99.999, 100) and not AttackActionResult.roll_hits(0.0, 0), "Strict roll boundary, 100% guarantee and zero chance remain honest")

	# Edit one shared resource: queries, commits and Guard must immediately agree.
	var tuning = CombatRules.cover_tuning
	_prepare(10)
	var old_damage: int = tuning.damage_on_hit
	var old_aim: int = tuning.aim_accuracy_bonus
	var old_guard: int = tuning.guard_accuracy_modifier
	tuning.damage_on_hit = 31
	tuning.aim_accuracy_bonus = 42
	tuning.guard_accuracy_modifier = -7
	check(tuning.damage_for_hit(0.35) == 11, "Shield reduction remains an independent defense applied to edited base damage")
	var aim_query := service.query_aim(actor.tactical_id)
	var aim := await service.submit_aim(service.make_aim_request(actor, TacticalActionRequest.Source.PLAYER), true)
	query = service.query_attack(actor.tactical_id, target.tactical_id)
	check(aim_query.accuracy_bonus == 42 and aim.accuracy_bonus == 42 and query.aim_bonus == 42 and query.hit_chance == 72 and query.damage_on_hit == 31, "Editing Aim and damage updates every authoritative query/commit")
	target.tactical_state.establish_overwatch()
	service._combat_rng = _rng(query.hit_chance, true, 23)
	var attack := await service.submit_attack(service.make_attack_request(actor, target, TacticalActionRequest.Source.PLAYER), true)
	check(attack != null and attack.did_hit and attack.damage == 31 and attack.reaction_events.size() == 1, "Edited damage reaches Attack and its Guard retaliation")
	if attack != null and not attack.reaction_events.is_empty():
		var reaction := attack.reaction_events[0]
		check(reaction.hit_chance == 23 and reaction.did_hit and reaction.damage == 31, "Edited Guard -7 changes probability while preserving edited hit damage")
	tuning.damage_on_hit = old_damage
	tuning.aim_accuracy_bonus = old_aim
	tuning.guard_accuracy_modifier = old_guard

	_prepare(10)
	tuning.base_accuracy = 200
	actor.tactical_state.establish_aim()
	query = service.query_attack(actor.tactical_id, target.tactical_id)
	check(query.hit_chance == 100 and query.evaluation.raw_chance == 165, "Bonuses stack before the final ceiling")
	tuning.base_accuracy = 0
	query = service.query_attack(actor.tactical_id, target.tactical_id)
	check(query.hit_chance == 5 and query.evaluation.raw_chance == -35, "Bonuses stack before the final floor; Aim does not add onto a clamped base")
	tuning.base_accuracy = 100
	tuning.minimum_hit_chance = 20
	tuning.maximum_hit_chance = 90
	check(service.query_attack(actor.tactical_id, target.tactical_id).hit_chance == 65, "Editable limits preserve an in-range chance")
	_prepare(5)
	check(service.query_attack(actor.tactical_id, target.tactical_id).hit_chance == 90, "Editable ceiling reaches the real query")
	tuning.base_accuracy = 0
	check(service.query_attack(actor.tactical_id, target.tactical_id).hit_chance == 20, "Editable floor reaches the real query")
	tuning.base_accuracy = 100
	tuning.minimum_hit_chance = 5
	tuning.maximum_hit_chance = 100
	for invalid in [["damage_on_hit", 0], ["base_accuracy", -1], ["minimum_hit_chance", 101], ["maximum_hit_chance", -1], ["aim_accuracy_bonus", -1], ["guard_accuracy_modifier", 1]]:
		var original: Variant = tuning.get(invalid[0])
		tuning.set(invalid[0], invalid[1])
		check(not tuning.is_valid() and not service.query_attack(actor.tactical_id, target.tactical_id).is_legal(), "Invalid setting rejects rather than silently changing damage or chance: %s" % invalid[0])
		tuning.set(invalid[0], original)
	query = service.query_attack(actor.tactical_id, target.tactical_id)
	var text := TacticalFeedbackText.shot(query)
	check(text.contains("Damage on hit: 25") and text.contains("strongest only") and text.contains("Raw") and text.contains("limits 5–100"), "Prediction explains fixed hit damage, protection stacking and chance limits")
	_prepare(5)
	tuning.aim_accuracy_bonus = 0
	actor.tactical_state.establish_aim()
	query = service.query_attack(actor.tactical_id, target.tactical_id)
	check(query.aim_applied and query.aim_bonus == 0, "A zero configured Aim bonus still represents the active stance")
	var zero_aim_attack := await service.submit_attack(service.make_attack_request(actor, target, TacticalActionRequest.Source.PLAYER), true)
	check(zero_aim_attack != null and zero_aim_attack.aim_applied and not actor.tactical_state.is_aiming, "Attack consumes Aim even when its configured bonus is zero")
	tuning.aim_accuracy_bonus = old_aim
	level.queue_free()
	await process_frame
	await process_frame
	print("Accuracy and damage: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
