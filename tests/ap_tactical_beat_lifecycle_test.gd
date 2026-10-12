extends SceneTree

const UNIT_SCENE := preload("res://units/tactical_unit.tscn")

var failures := 0
var ui_layer: CanvasLayer

func _initialize() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.add_to_group("UI_LAYER")
	root.add_child(ui_layer)
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	await _check_mixed_roster_and_zero_capacity()
	await _check_free_objective_exception()
	await _check_modifier_lifecycle()
	await _check_beat_casualty_before_refresh()
	print("AP tactical-beat lifecycle: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _make_unit(id: StringName, faction: TacticalUnit.Faction, base_ap: int) -> TacticalUnit:
	var unit := UNIT_SCENE.instantiate() as TacticalUnit
	unit.tactical_id = id
	unit.faction = faction
	root.add_child(unit)
	unit.stats.configure_base_ap(base_ap, true)
	return unit

func _make_turns(players: Array[TacticalUnit], allies: Array[TacticalUnit], enemies: Array[TacticalUnit]) -> TurnManager:
	var turns := TurnManager.new()
	turns.automatic_annihilation_results = false
	turns.player_units = players
	turns.allied_units = allies
	turns.enemy_units = enemies
	root.add_child(turns)
	return turns

func _check_mixed_roster_and_zero_capacity() -> void:
	var zero := _make_unit(&"zero", TacticalUnit.Faction.PLAYER, 0)
	var two := _make_unit(&"two", TacticalUnit.Faction.PLAYER, 2)
	var four := _make_unit(&"four", TacticalUnit.Faction.PLAYER, 4)
	var ally_zero := _make_unit(&"ally_zero", TacticalUnit.Faction.ALLY, 0)
	var enemy_zero := _make_unit(&"enemy_zero", TacticalUnit.Faction.ENEMY, 0)
	var turns := _make_turns([zero, two, four], [ally_zero], [enemy_zero])
	var exhausted_events := [0]
	turns.player_actions_exhausted.connect(func(): exhausted_events[0] += 1)
	turns.start_battle()
	check(turns.active_unit == two, "Phase start skips a zero-capacity player and selects the first ordinary actor")
	check(zero.stats.current_ap == 0 and two.stats.current_ap == 2 and four.stats.current_ap == 4, "Mixed 0/2/4 AP roster refreshes from each unit's effective maximum")
	two.stats.spend_all_remaining_ap()
	await process_frame
	check(turns.active_unit == four, "Exhaustion advances once to the next eligible player")
	four.stats.spend_all_remaining_ap()
	await process_frame
	check(exhausted_events[0] == 1, "An all-exhausted player roster emits one phase-completion prompt")
	turns.end_current_turn()
	check(turns.current_phase == TurnManager.TurnPhase.PLAYER_TURN and turns.current_round == 2, "All-zero ally and enemy rosters pass through to the next tactical beat without stalling")
	check(turns.active_unit == two and two.stats.current_ap == 2, "The next player phase performs one legitimate activation refresh")
	_free_nodes([turns, zero, two, four, ally_zero, enemy_zero])
	await process_frame

func _check_free_objective_exception() -> void:
	var free_actor := _make_unit(&"free", TacticalUnit.Faction.PLAYER, 0)
	var ordinary := _make_unit(&"ordinary", TacticalUnit.Faction.PLAYER, 3)
	var has_free := [true]
	var turns := _make_turns([free_actor, ordinary], [], [])
	turns.free_objective_action_available = func(actor: TacticalUnit): return actor == free_actor and has_free[0]
	turns.start_battle()
	check(turns.active_unit == free_actor and free_actor.stats.current_ap == 0, "A zero-AP actor remains eligible only for a legal free objective action")
	has_free[0] = false
	turns.complete_free_objective_action(free_actor)
	await process_frame
	check(turns.active_unit == ordinary, "After the free action is no longer legal, selection advances to an ordinary actor")
	_free_nodes([turns, free_actor, ordinary])
	await process_frame

func _check_modifier_lifecycle() -> void:
	var actor := _make_unit(&"tempo", TacticalUnit.Faction.PLAYER, 3)
	var turns := _make_turns([actor], [], [])
	turns.start_battle()
	actor.stats.consume_ap(1)
	actor.stats.set_ap_modifier(&"fixture:penalty", -1)
	check(actor.stats.current_ap == 1 and actor.stats.activation_capacity_ap == 2, "A mid-activation penalty preserves expenditure and ratchets capacity")
	actor.stats.remove_ap_modifier(&"fixture:penalty")
	check(actor.stats.current_ap == 1 and actor.stats.activation_capacity_ap == 2, "Penalty removal grants no AP in the same activation")
	actor.stats.set_ap_modifier(&"fixture:bonus", 1)
	check(actor.stats.current_ap == 1 and actor.stats.effective_max_ap == 4, "A positive modifier waits for the next refresh")
	actor.stats.spend_all_remaining_ap()
	await process_frame
	turns.end_current_turn()
	check(actor.stats.current_ap == 4 and actor.stats.activation_capacity_ap == 4 and actor.stats.spent_ap == 0, "The next phase refresh adopts the new effective maximum and clears expenditure")
	_free_nodes([turns, actor])
	await process_frame

func _check_beat_casualty_before_refresh() -> void:
	var doomed := _make_unit(&"doomed", TacticalUnit.Faction.PLAYER, 3)
	var survivor := _make_unit(&"survivor", TacticalUnit.Faction.PLAYER, 3)
	var turns := _make_turns([doomed, survivor], [], [])
	doomed.stats.current_hp = 1
	doomed.stats.defeated.connect(func(): turns.remove_unit(doomed))
	turns.tactical_beat_ended.connect(func(_beat: int): doomed.stats.take_damage(1))
	turns.start_battle()
	turns.end_current_turn()
	check(doomed.stats.is_defeated and not turns.player_units.has(doomed), "Beat damage resolves defeat before the new player phase refresh")
	check(turns.current_round == 2 and turns.active_unit == survivor and survivor.stats.current_ap == 3, "A beat casualty cannot receive AP or hold selection in the next round")
	_free_nodes([turns, doomed, survivor])
	await process_frame

func _free_nodes(nodes: Array) -> void:
	for node in nodes:
		if is_instance_valid(node):
			node.queue_free()
