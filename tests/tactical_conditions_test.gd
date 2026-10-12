extends SceneTree

const BATTLE_SCENE := preload("res://levels/prototype_map/prototype_map.tscn")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	_check_definition_expiration()
	await _check_lifecycle_susceptibility_and_treatment()
	await _check_attack_hazard_and_replay_facts()
	await _check_periodic_defeat_recovery()
	_check_historical_compatibility()
	print("Tactical conditions: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_definition_expiration() -> void:
	var component := ConditionComponent.new()
	component.apply(ConditionCatalog.LEAKING, 1, &"fixture")
	component.tick(1)
	component.tick(2)
	check(component.has(&"leaking"), "A three-beat condition remains active through its second tick")
	var final_events := component.tick(3)
	check(not component.has(&"leaking") and final_events.size() == 1 and final_events[0].remaining_beats == 0, "A condition expires deterministically after its configured beat count")
	component.free()

func _check_lifecycle_susceptibility_and_treatment() -> void:
	var level := await _create_battle()
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var service := level.battle_controller.action_service
	var hp_before := actor.stats.current_hp
	var first := service.apply_condition(actor, ConditionCatalog.LEAKING, &"fixture")
	check(first.applied and actor.conditions.has(&"leaking") and actor.stats.current_hp == hp_before, "Leaking applies without immediate damage")
	var droplets := actor.get_node_or_null("LeakingDroplets") as CPUParticles3D
	check(droplets != null and droplets.emitting, "Leaking creates the lightweight droplet presentation")
	service.apply_condition(actor, ConditionCatalog.LEAKING, &"refresh")
	check(actor.conditions.active[&"leaking"].remaining_beats == 3 and actor.conditions.active.size() == 1, "Leaking refreshes one non-stacking instance")
	level.turn_manager.tactical_beat_ended.emit(level.turn_manager.current_round)
	check(actor.stats.current_hp == hp_before - 1 and actor.conditions.active[&"leaking"].remaining_beats == 2, "Leaking deals one damage at the next tactical-beat boundary")
	actor.tactical_state.establish_aim()
	var jam := service.apply_condition(actor, ConditionCatalog.JAMMED, &"fixture")
	check(jam.applied and not actor.tactical_state.is_aiming and service.query_aim(actor.tactical_id).validation.code == &"condition_restriction", "Jammed cancels existing Aim and authoritatively restricts new Aim")
	var biological := level.turn_manager.player_units[1]
	biological.condition_susceptibilities = ConditionDefinition.Susceptibility.BIOLOGICAL
	check(not service.apply_condition(biological, ConditionCatalog.LEAKING, &"fixture").applied, "Biological-only actors reject Leaking")
	check(service.apply_condition(biological, ConditionCatalog.BLEEDING, &"fixture").applied, "Bleeding applies to susceptible biological actors")
	var hp_damaged := actor.stats.current_hp
	var ap_before := actor.stats.current_ap
	var charges_before := actor.emergency_seal_charges
	var seal := await service.submit_simple(service.make_simple_request(&"emergency_seal", actor, TacticalActionRequest.Source.PLAYER), true)
	check(seal != null and not actor.conditions.has(&"leaking") and actor.stats.current_hp == hp_damaged, "Emergency Seal removes Leaking without restoring HP")
	check(actor.stats.current_ap == ap_before - 1 and actor.emergency_seal_charges == charges_before - 1, "Emergency Seal consumes exactly one AP and one charge")
	check(not droplets.emitting, "Emergency Seal stops the droplet presentation immediately")
	var rejected_ap := actor.stats.current_ap
	check(await service.submit_simple(service.make_simple_request(&"emergency_seal", actor, TacticalActionRequest.Source.PLAYER), true) == null and actor.stats.current_ap == rejected_ap, "Invalid treatment consumes no AP or charge")
	actor.stats.current_ap = 1
	actor.emergency_seal_charges = 1
	service.apply_condition(actor, ConditionCatalog.LEAKING, &"fixture")
	var ai := AIController.new()
	ai.unit = actor
	ai.turn_manager = level.turn_manager
	ai.battle_controller = level.battle_controller
	check(await ai.call("_try_emergency_seal") and not actor.conditions.has(&"leaking") and actor.emergency_seal_charges == 0, "AI self-treats Leaking through the shared authoritative action")
	ai.free()
	level.queue_free()
	await process_frame

func _check_attack_hazard_and_replay_facts() -> void:
	var level := await _create_battle()
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var target: TacticalUnit = level.turn_manager.enemy_units[0]
	var service := level.battle_controller.action_service
	_prepare_attack(level, actor, target)
	actor.attack_condition = ConditionCatalog.LEAKING
	service._combat_rng.seed = 1
	var attack := await service.submit_attack(service.make_attack_request(actor, target, TacticalActionRequest.Source.PLAYER), true)
	check(attack != null and attack.did_hit and attack.damage > 0 and attack.condition_events.size() == 1 and target.conditions.has(&"leaking"), "Configured successful damaging Attack applies Leaking inside its parent transaction")
	check(attack.to_replay_record().resolved.condition_events.size() == 1, "Attack replay facts include nested condition application")
	var ordinary := level.turn_manager.player_units[1]
	check(ordinary.attack_condition == null, "Ordinary attacks do not carry an implicit Leaking property")
	level.turn_manager.call("_set_active_unit", ordinary)
	var move_inventory := service.query_move(ordinary.tactical_id)
	var destination: Vector3i = move_inventory.legal_destination_cells[0]
	if destination == level.battle_controller.grid_manager.get_unit_grid(ordinary) and move_inventory.legal_destination_cells.size() > 1:
		destination = move_inventory.legal_destination_cells[1]
	var preview := service.query_move(ordinary.tactical_id, destination)
	if preview.path_cells.size() > 1:
		level.battle_controller.grid_manager.map_data.get_cell(preview.path_cells[1]).hazard_condition = ConditionCatalog.JAMMED
	var move := await service.submit_move(service.make_move_request(ordinary, destination, TacticalActionRequest.Source.PLAYER), true)
	check(move != null and move.condition_events.size() == 1 and ordinary.conditions.has(&"jammed"), "Entering an electrified checkpoint applies Jammed before movement reactions")
	check(move.to_replay_record().resolved.condition_events.size() == 1, "Move replay facts keep hazard exposure inside the parent transaction")
	level.queue_free()
	await process_frame

func _check_periodic_defeat_recovery() -> void:
	var level := await _create_battle()
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	actor.stats.current_hp = 1
	level.battle_controller.action_service.apply_condition(actor, ConditionCatalog.LEAKING, &"fixture")
	level.turn_manager.tactical_beat_ended.emit(level.turn_manager.current_round)
	await process_frame
	check(actor.stats.is_defeated and not level.turn_manager.player_units.has(actor), "Periodic condition damage uses the normal authoritative defeat/removal lifecycle")
	level.queue_free()
	await process_frame

func _check_historical_compatibility() -> void:
	var legacy := BattleConfiguration.new()
	legacy.apply_replay({"player_count": 1, "enemy_count": 1, "supply_points_enabled": true, "aim_enabled": true, "shield_enabled": true, "overwatch_enabled": true})
	check(not legacy.conditions_enabled, "Historical recordings without condition metadata retain pre-condition semantics")
	check(BattleConfiguration.new().to_replay().conditions_enabled, "New battles record condition semantics explicitly")

func _create_battle() -> BattleLevel:
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	level.configure(2, 1, false, 12012, 0, Vector2i(32, 24), false, MissionActor.VIPBehavior.PLAYER_CONTROLLED, MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 1, false))
	root.add_child(level)
	while level.turn_manager.current_round == 0: await process_frame
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	return level

func _prepare_attack(level: BattleLevel, actor: TacticalUnit, target: TacticalUnit) -> void:
	var grid := level.battle_controller.grid_manager
	var old_target := grid.get_unit_grid(target)
	var target_cell := grid.get_unit_grid(actor) + Vector3i.RIGHT
	var cell := grid.get_cell_data(target_cell)
	cell.cover_type = MapCellData.CoverType.NONE
	cell.cover_height = 0.0
	cell.blocks_line_of_sight = false
	grid.map_data.rebuild_los_index()
	target.global_position = grid.grid_to_world(target_cell) + Vector3.UP * target.standing_height
	grid.update_unit_position(target, old_target, target_cell)
