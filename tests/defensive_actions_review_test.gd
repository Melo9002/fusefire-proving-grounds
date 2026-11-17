extends SceneTree
## Step-8 contract: explain real reaction checks and use physical Shield direction.
const BattleScene := preload("res://levels/prototype_map/prototype_map.tscn")
var failures := 0
var checks := 0
var level: BattleLevel
var actor: TacticalUnit
var enemy: TacticalUnit
var grid: GridManager
var service: TacticalActionService

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _place(unit: TacticalUnit, cell: Vector3i) -> void:
	grid.update_unit_position(unit, unit.grid_position, cell)
	unit.global_position = grid.grid_to_world(cell) + Vector3.UP * unit.standing_height

func _enemy_activation() -> void:
	level.turn_manager.current_phase = TurnManager.TurnPhase.ENEMY_TURN
	level.turn_manager.active_unit = enemy
	enemy.stats.set_available_ap_for_setup(3)

func _force_guard_miss() -> void:
	for candidate_seed in 10000:
		var rng := RandomNumberGenerator.new()
		rng.seed = candidate_seed
		if rng.randf() * 100.0 >= 85:
			service._combat_rng.seed = candidate_seed
			return
	check(false, "An 85% Guard miss seed exists")

func _capture(name: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "capture" or DisplayServer.get_name() == "headless": return
	root.size = Vector2i(1440, 900)
	var rig := level.get_node("CameraRig") as TacticalCamera
	rig.set_process(false)
	rig._cancel_selection_focus()
	var focus := (actor.global_position + enemy.global_position) * 0.5
	rig.camera.global_position = focus + Vector3(10, 15, 13)
	rig.camera.look_at(focus)
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(args[1])
	check(root.get_texture().get_image().save_png(args[1].path_join(name + ".png")) == OK, "Saved defensive UI review: " + name)

func _run() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.TACTICAL_TEST_RANGE)
	config.player_count = 1
	config.enemy_count = 2
	config.player_archetypes = [&"shieldbearer"]
	config.content_manifest = {"population_enabled": false}
	level = BattleScene.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	check(level.battle_initialization_succeeded, "Current selectable range initializes")
	if not level.battle_initialization_succeeded:
		level.free()
		quit(1)
		return
	actor = level.turn_manager.player_units[0]
	enemy = level.turn_manager.enemy_units[0]
	grid = level.battle_controller.grid_manager
	service = level.battle_controller.action_service
	_place(actor, Vector3i(1, 0, 22))
	_place(enemy, Vector3i(2, 0, 23))
	actor.attack_range = 10
	enemy.attack_range = 10
	var source_point := grid.grid_to_world(actor.grid_position)
	var target_point := grid.grid_to_world(enemy.grid_position)
	grid.get_cell_data(actor.grid_position).world_position.x += 0.4
	grid.get_cell_data(enemy.grid_position).world_position.x -= 0.4
	var shield_query := service.query_shield(actor.tactical_id, enemy.tactical_id)
	check(shield_query.is_legal() and shield_query.facing.is_equal_approx(Vector2(0.2, 1).normalized()), "Shield faces the actual supported point, not the diagonal between cells")
	actor.tactical_state.establish_shield(Vector2.RIGHT)
	var protection := CombatRules.get_shield_protection(enemy, actor, grid)
	check(not protection.applied and protection.reason == "Outside Shield arc", "A cell-center diagonal inside the arc does not protect a physically outside attacker")
	check(not CombatRules.get_shield_protection_at_cells(enemy.grid_position, actor, actor.grid_position, grid).applied, "Checkpoint and live Shield direction agree")
	_enemy_activation()
	var shifted_query := service.query_attack(enemy.tactical_id, actor.tactical_id)
	var shifted_prediction := CombatRules.evaluate_attack_from_cell(enemy, enemy.grid_position, actor, grid, null)
	enemy.tactical_state.establish_overwatch()
	var shifted_guard := service.query_guard_reaction(enemy, actor)
	check(shifted_query.is_legal() and not shifted_query.shield_applied and shifted_query.damage_on_hit == 25 and not shifted_prediction.shield_applied, "Authoritative query and proposed-source preview use the physical outside-arc direction")
	check(TacticalFeedbackText.shot(shifted_query).contains("Outside Shield arc"), "Shot preview explains why an active Shield does not protect this direction")
	check(shifted_guard.can_fire and not shifted_guard.evaluation.shield_applied, "Guard uses the same shifted direction as the ordinary shot")
	enemy.tactical_state.clear_overwatch()
	var shifted_attack := await service.submit_attack(service.make_attack_request(enemy, actor, TacticalActionRequest.Source.AI), true)
	check(shifted_attack != null and shifted_attack.did_hit and not shifted_attack.shield_applied and shifted_attack.damage == shifted_query.damage_on_hit, "Committed offset shot agrees with its prediction rather than the old cell-center protection")
	actor.stats.current_hp = 100
	enemy.stats.current_supply_points = 4
	level.turn_manager.current_phase = TurnManager.TurnPhase.PLAYER_TURN
	level.turn_manager.active_unit = actor
	for angle in [0.0, PI / 2, PI, 3 * PI / 2]:
		var facing := Vector2.RIGHT.rotated(angle)
		check(CombatRules.is_within_protected_arc(facing, facing.rotated(deg_to_rad(60)), 120) and not CombatRules.is_within_protected_arc(facing, facing.rotated(deg_to_rad(60.1)), 120), "Inclusive boundary remains stable after rotation %s" % angle)
	grid.get_cell_data(actor.grid_position).world_position = source_point
	grid.get_cell_data(enemy.grid_position).world_position = target_point
	_place(enemy, Vector3i(2, 0, 24))
	target_point = grid.grid_to_world(enemy.grid_position)
	grid.get_cell_data(actor.grid_position).world_position += Vector3(-0.4, 0, 0.4)
	grid.get_cell_data(enemy.grid_position).world_position += Vector3(0.4, 0, -0.4)
	check(CombatRules.get_shield_protection(enemy, actor, grid).applied, "A physically inside attacker is protected even when the cell-center angle is outside")
	# Actual authored stacked galleries have no horizontal bearing to commit.
	grid.get_cell_data(actor.grid_position).world_position = source_point
	grid.get_cell_data(enemy.grid_position).world_position = target_point
	_place(actor, Vector3i(6, 3, 6))
	_place(enemy, Vector3i(6, 6, 6))
	actor.tactical_state.reset()
	var ap_before := actor.stats.current_ap
	check(service.query_shield(actor.tactical_id, enemy.tactical_id).validation.code == &"invalid_direction", "A directly overhead target cannot create a zero-facing Shield stance")
	check(await service.submit_shield(service.make_shield_request(actor, enemy, TacticalActionRequest.Source.PLAYER), true) == null and actor.stats.current_ap == ap_before, "Invalid facing spends no AP")
	_place(actor, Vector3i(1, 0, 22))
	_place(enemy, Vector3i(1, 0, 16))
	var shield := await service.submit_shield(service.make_shield_request(actor, enemy, TacticalActionRequest.Source.PLAYER), true)
	check(shield != null and actor.stats.current_ap == ap_before - 1 and actor.tactical_state.is_shielding, "Shield commits its one-AP cost and fixed facing")
	var hud := level.get_node("Visualizers/BattleUI/ActionHUDController") as ActionHUDController
	hud._update_button_states()
	check(hud.shield_button.tooltip_text.contains("120°") and hud.shield_button.tooltip_text.contains("×0.35") and hud.shield_button.tooltip_text.contains("does not track") and hud.shield_button.tooltip_text.contains("next activation"), "Shield explains benefits, fixed direction, restrictions and expiry")
	check(hud.tactical_state_label.text == "SHIELD 120° FRONT", "Shield status describes its arc rather than presenting vector components as angles")
	check(hud.aim_button.tooltip_text.contains("No damage bonus") and hud.aim_button.tooltip_text.contains("does not stack"), "Aim explains accuracy-only benefit and non-stacking")
	check(hud.overwatch_button.tooltip_text.contains("no facing cone") and hud.overwatch_button.tooltip_text.contains("Blocked/out-of-range") and hud.overwatch_button.tooltip_text.contains("even on a miss"), "Guard explains direction, legal opportunities and one-shot consumption")
	var capability := actor.shield_capability
	actor.shield_capability = null
	hud._update_button_states()
	check(hud.tactical_state_label.text == "SHIELD (unavailable)", "Stale Shield state without a capability is reported safely")
	actor.shield_capability = capability.duplicate()
	actor.shield_capability.attacks_allowed = true
	actor.shield_capability.reload_allowed = true
	hud._update_button_states()
	check(hud.shield_button.tooltip_text.contains("does not restrict Attack or Reload"), "Shield tooltip follows configured action permissions")
	actor.shield_capability = capability
	hud._update_button_states()
	await _capture("shield-active")
	var wait_rng := service.get_combat_rng_state()
	var skipped := await service.submit_simple(service.make_simple_request(&"wait", actor, TacticalActionRequest.Source.PLAYER), true)
	check(skipped != null and actor.stats.current_ap == 0 and actor.tactical_state.is_shielding, "Skipping remaining AP preserves Shield for the enemy turn")
	check(service.get_combat_rng_state() == wait_rng and CombatRules.evaluate_attack(enemy, actor, grid, null).shield_applied, "Skipping rolls nothing and retains frontal protection")
	await _capture("shield-skipped")
	actor.stats.set_available_ap_for_setup(2)
	check(not service.query_overwatch(actor.tactical_id).is_legal(), "Shield and Guard cannot combine")
	var aim := await service.submit_aim(service.make_aim_request(actor, TacticalActionRequest.Source.PLAYER), true)
	check(aim != null and actor.tactical_state.is_aiming and not actor.tactical_state.is_shielding, "Aim spends one AP and deliberately replaces Shield")
	var guard := await service.submit_overwatch(service.make_overwatch_request(actor, TacticalActionRequest.Source.PLAYER), true)
	check(guard != null and actor.stats.current_ap == 0 and not actor.tactical_state.is_aiming and actor.tactical_state.is_overwatching and actor.stats.current_supply_points == 4, "Guard spends remaining AP, cancels Aim and reserves rather than spends SP")
	var rng_before := service.get_combat_rng_state()
	var fingerprint := BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager)
	check(service.query_guard_reaction(actor, enemy).can_fire, "Reserved Guard can react with zero AP outside its activation")
	actor.stats.current_supply_points = 0
	check(service.query_guard_reaction(actor, enemy).reason.contains("SP"), "Guard explains missing reaction ammo")
	actor.stats.current_supply_points = 4
	actor.attack_range = 1
	check(service.query_guard_reaction(actor, enemy).reason == "Out of range", "Guard explains weapon reach using actual shot rules")
	actor.attack_range = 10
	enemy.faction = actor.faction
	check(service.query_guard_reaction(actor, enemy).reason == "Not hostile", "Guard does not react to friendly movement")
	enemy.faction = TacticalUnit.Faction.ENEMY
	actor.carried_unit = enemy
	check(service.query_guard_reaction(actor, enemy).reason == "Cannot shoot while carrying", "Guard respects the same carrying restriction as an ordinary shot")
	actor.carried_unit = null
	check(rng_before == service.get_combat_rng_state() and fingerprint == BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager), "Read-only Guard checks consume no RNG or authoritative state")
	_enemy_activation()
	var enemy_aim := await service.submit_aim(service.make_aim_request(enemy, TacticalActionRequest.Source.AI), true)
	check(enemy_aim != null and actor.tactical_state.is_overwatching and actor.stats.current_supply_points == 4 and rng_before == service.get_combat_rng_state(), "An enemy's Aim is not a Guard trigger")
	var blocker := grid.get_cell_data(Vector3i(1, 0, 19))
	var old_height := blocker.cover_height
	var old_los := blocker.blocks_line_of_sight
	blocker.cover_height = 4
	blocker.blocks_line_of_sight = true
	grid.map_data.rebuild_los_index()
	check(service.query_guard_reaction(actor, enemy).reason == "Blocked", "Guard reports obstruction from shared body-sample LOS")
	var blocked_move := await service.submit_move(service.make_move_request(enemy, Vector3i(1, 0, 17), TacticalActionRequest.Source.AI), true)
	check(blocked_move != null and blocked_move.reaction_events.is_empty() and blocked_move.guard_checks[actor.tactical_id].reason == "Blocked", "A real blocked Move retains a concrete no-fire explanation")
	check(actor.tactical_state.is_overwatching and actor.stats.current_supply_points == 4 and rng_before == service.get_combat_rng_state(), "A blocked opportunity preserves Guard, SP and RNG")
	check("\n".join(TacticalFeedbackText.committed(blocked_move)).contains("Reaction still reserved"), "Combat log explains that a skipped reaction remains available")
	await _capture("guard-blocked")
	blocker.cover_height = old_height
	blocker.blocks_line_of_sight = old_los
	grid.map_data.rebuild_los_index()
	actor.attack_range = 1
	_enemy_activation()
	var ranged_move := await service.submit_move(service.make_move_request(enemy, Vector3i(1, 0, 18), TacticalActionRequest.Source.AI), true)
	check(ranged_move != null and ranged_move.reaction_events.is_empty() and ranged_move.guard_checks[actor.tactical_id].reason == "Out of range", "Real movement outside range explains why Guard did not fire")
	actor.attack_range = 10
	_enemy_activation()
	_force_guard_miss()
	var fired_move := await service.submit_move(service.make_move_request(enemy, Vector3i(1, 0, 17), TacticalActionRequest.Source.AI), true)
	check(fired_move != null and fired_move.reaction_events.size() == 1 and fired_move.guard_checks.is_empty(), "An eligible checkpoint fires once and clears earlier skip diagnostics")
	check(fired_move.reaction_events.size() == 1 and not fired_move.reaction_events[0].did_hit and fired_move.reaction_events[0].damage == 0, "Controlled Guard miss deals zero damage")
	check(not actor.tactical_state.is_overwatching and actor.stats.current_supply_points == 3, "A reaction spends one SP and the reservation, hit or miss")
	check("\n".join(TacticalFeedbackText.committed(fired_move)).contains("movement at"), "Reaction feedback identifies the triggering movement checkpoint")
	await _capture("guard-miss")
	# Expiry is observable once, without inventing a shot or consuming randomness.
	actor.tactical_state.establish_overwatch()
	rng_before = service.get_combat_rng_state()
	actor.tactical_state.begin_activation(77, 0)
	check(not actor.tactical_state.is_overwatching and level.battle_controller.combat_log[-1].contains("Guard (unused) expired"), "Unused Guard expiry is explained at the next activation")
	var log_before := level.battle_controller.combat_log.duplicate()
	actor.tactical_state.begin_activation(77, 0)
	check(level.battle_controller.combat_log == log_before and rng_before == service.get_combat_rng_state(), "Same-activation selection neither expires twice nor rolls")
	actor.tactical_state.establish_aim()
	actor.tactical_state.begin_activation(78, 0)
	check(level.battle_controller.combat_log[-1].contains("Aim expired"), "Aim expiry is explained")
	actor.tactical_state.establish_shield(Vector2.RIGHT)
	actor.tactical_state.begin_activation(79, 0)
	check(level.battle_controller.combat_log[-1].contains("Shield expired"), "Shield expiry is explained")
	actor.tactical_state.establish_overwatch()
	actor.stats.current_supply_points = 4
	_enemy_activation()
	var attack := await service.submit_attack(service.make_attack_request(enemy, actor, TacticalActionRequest.Source.AI), true)
	check(attack != null and attack.reaction_events.size() == 1 and attack.reaction_events[0].checkpoint_index == 0, "A surviving directly attacked watcher retaliates")
	check("\n".join(TacticalFeedbackText.committed(attack)).contains("retaliation after being attacked"), "Retaliation explains its distinct trigger")
	# A guaranteed ordinary hit kills the watcher before its reserved response.
	actor.stats.current_hp = 25
	actor.tactical_state.establish_overwatch()
	actor.stats.current_supply_points = 4
	_enemy_activation()
	var lethal := await service.submit_attack(service.make_attack_request(enemy, actor, TacticalActionRequest.Source.AI), true)
	check(lethal != null and lethal.target_defeated and lethal.reaction_events.is_empty() and lethal.guard_checks[actor.tactical_id].reason.contains("defeated"), "A dead watcher cannot retaliate and reports why")
	check(actor.stats.current_supply_points == 4 and not actor.tactical_state.is_overwatching, "Defeat clears Guard without spending reaction SP")
	level.queue_free()
	await process_frame
	await process_frame
	print("Defensive action review: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
