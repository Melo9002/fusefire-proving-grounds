extends SceneTree

const BATTLE_SCENE := preload("res://levels/prototype_map/prototype_map.tscn")
const UNIT_SCENE := preload("res://units/tactical_unit.tscn")
const SYSTEM_OVERLOAD := preload("res://tests/fixtures/system_overload.tres")
const OVERLOAD_MODIFIER := &"condition:system_overload"

var failures := 0
var ui_layer: CanvasLayer

func _initialize() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.add_to_group("UI_LAYER")
	root.add_child(ui_layer)
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	await _check_application_refresh_removal_and_expiry()
	await _check_rejection_and_existing_conditions()
	await _check_zero_capacity_progression_and_defeat_cleanup()
	print("Condition AP tempo integration: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_application_refresh_removal_and_expiry() -> void:
	var level := await _create_battle()
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var service := level.battle_controller.action_service
	actor.stats.consume_ap(1)
	var applied := service.apply_condition(actor, SYSTEM_OVERLOAD, &"fixture")
	check(applied.applied and actor.stats.effective_max_ap == 2, "System Overload applies one -1 effective maximum AP modifier")
	check(actor.stats.activation_capacity_ap == 2 and actor.stats.spent_ap == 1 and actor.stats.current_ap == 1, "Condition application preserves expenditure and ratchets activation capacity")
	check(actor.stats.get_ap_modifier_snapshot().count({"source_id": OVERLOAD_MODIFIER, "delta": -1}) == 1, "Condition owns one stable AP modifier source")
	actor.conditions.tick(level.turn_manager.current_round)
	var refreshed := service.apply_condition(actor, SYSTEM_OVERLOAD, &"refresh")
	check(refreshed.refreshed and actor.conditions.active[&"system_overload"].remaining_beats == 2, "Reapplication refreshes duration")
	check(actor.stats.get_ap_modifier_snapshot().count({"source_id": OVERLOAD_MODIFIER, "delta": -1}) == 1, "Reapplication replaces rather than stacks the AP modifier")
	actor.stats.set_ap_modifier(&"equipment:test_penalty", -1)
	var overlap := actor.stats.get_ap_modifier_snapshot()
	check(actor.stats.effective_max_ap == 1 and overlap.size() == 2, "Condition and independent modifiers coexist")
	actor.stats.remove_ap_modifier(&"equipment:test_penalty")
	actor.stats.set_ap_modifier(&"equipment:test_penalty", -1)
	check(actor.stats.get_ap_modifier_snapshot() == overlap, "Overlapping modifier evidence is independent of insertion history")
	var removals := [0]
	actor.conditions.condition_removed.connect(func(id: StringName):
		if id == &"system_overload": removals[0] += 1
	)
	check(actor.conditions.remove(&"system_overload"), "Explicit condition removal succeeds")
	check(not actor.stats.has_ap_modifier(OVERLOAD_MODIFIER) and actor.stats.has_ap_modifier(&"equipment:test_penalty"), "Removal clears only the condition-owned modifier")
	check(actor.stats.current_ap == 0 and actor.stats.activation_capacity_ap == 1, "Removal does not refund AP or raise ratcheted capacity")
	check(not actor.conditions.remove(&"system_overload") and removals[0] == 1, "Repeated removal is harmless and cleanup occurs exactly once")
	actor.stats.remove_ap_modifier(&"equipment:test_penalty")
	service.apply_condition(actor, SYSTEM_OVERLOAD, &"expiry")
	actor.conditions.tick(level.turn_manager.current_round)
	actor.conditions.tick(level.turn_manager.current_round + 1)
	check(not actor.conditions.has(&"system_overload") and not actor.stats.has_ap_modifier(OVERLOAD_MODIFIER), "Expiration removes the condition modifier")
	check(actor.stats.current_ap == 0 and actor.stats.activation_capacity_ap == 1, "Expiration does not restore availability in the current activation")
	actor.stats.refresh_activation()
	check(actor.stats.effective_max_ap == 3 and actor.stats.activation_capacity_ap == 3 and actor.stats.current_ap == 3, "The next activation refresh restores AP from the recovered effective maximum")
	level.queue_free()
	await process_frame

func _check_rejection_and_existing_conditions() -> void:
	var level := await _create_battle()
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var immune: TacticalUnit = level.turn_manager.player_units[1]
	var service := level.battle_controller.action_service
	immune.condition_immunities.append(&"system_overload")
	var before := immune.stats.get_ap_snapshot()
	var rejected := service.apply_condition(immune, SYSTEM_OVERLOAD, &"fixture")
	check(not rejected.applied and immune.stats.get_ap_snapshot() == before, "Immunity rejects System Overload without changing AP")
	actor.tactical_state.establish_aim()
	service.apply_condition(actor, ConditionCatalog.JAMMED, &"fixture")
	check(not actor.tactical_state.is_aiming and actor.conditions.restricts(&"aim"), "Jammed still cancels and restricts Aim")
	check(actor.stats.get_ap_modifier_snapshot().is_empty() and actor.stats.effective_max_ap == 3, "Jammed does not apply an AP penalty")
	var hp_before := actor.stats.current_hp
	var ap_before := actor.stats.get_ap_snapshot()
	service.apply_condition(actor, ConditionCatalog.LEAKING, &"fixture")
	level.turn_manager.tactical_beat_ended.emit(level.turn_manager.current_round)
	check(actor.stats.current_hp == hp_before - 1, "Leaking retains its one-point periodic damage")
	check(actor.stats.get_ap_snapshot() == ap_before, "Leaking does not change AP state")
	level.queue_free()
	await process_frame

func _check_zero_capacity_progression_and_defeat_cleanup() -> void:
	var overloaded := _make_unit(&"overloaded", 1)
	var ordinary := _make_unit(&"ordinary", 3)
	overloaded.conditions.apply(SYSTEM_OVERLOAD, 1, &"fixture")
	var turns := TurnManager.new()
	turns.automatic_annihilation_results = false
	turns.player_units = [overloaded, ordinary]
	root.add_child(turns)
	turns.start_battle()
	check(overloaded.stats.effective_max_ap == 0 and overloaded.stats.current_ap == 0, "System Overload can reduce effective and available AP to zero")
	check(turns.active_unit == ordinary, "A zero-capacity conditioned actor cannot stall player selection")
	overloaded.stats.current_hp = 1
	overloaded.stats.take_damage(1)
	check(not overloaded.stats.has_ap_modifier(OVERLOAD_MODIFIER) and overloaded.conditions.active.is_empty(), "Defeat clears condition-owned modifiers")
	turns.queue_free()
	overloaded.queue_free()
	ordinary.queue_free()
	await process_frame

func _make_unit(id: StringName, base_ap: int) -> TacticalUnit:
	var unit := UNIT_SCENE.instantiate() as TacticalUnit
	unit.tactical_id = id
	unit.faction = TacticalUnit.Faction.PLAYER
	root.add_child(unit)
	unit.stats.configure_base_ap(base_ap, true)
	return unit

func _create_battle() -> BattleLevel:
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	level.configure(2, 1, false, 13134, 0, Vector2i(32, 24), false, MissionActor.VIPBehavior.PLAYER_CONTROLLED, MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 1, false))
	root.add_child(level)
	while level.turn_manager.current_round == 0:
		await process_frame
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	return level
