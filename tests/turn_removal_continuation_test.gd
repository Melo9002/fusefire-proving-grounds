extends SceneTree
## Two pending removals may observe the same empty player phase before yielding.
## Only one may end that phase; neither may consume an allied activation.
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var turns := TurnManager.new()
	root.add_child(turns)
	var units: Array[TacticalUnit] = []
	for index in 3:
		var unit := load("res://units/tactical_unit.tscn").instantiate() as TacticalUnit
		unit.show_world_hud = false
		unit.name = "RemovalFixture%d" % index
		root.add_child(unit)
		units.append(unit)
	turns.allied_units.assign([units[0], units[1]])
	turns.enemy_units.assign([units[2]])
	turns.current_round = 1
	turns.current_phase = TurnManager.TurnPhase.PLAYER_TURN
	var commands := [0]
	turns.turn_ended.connect(func(_record): commands[0] += 1)
	turns._continue_after_active_unit_removed(true, false, false)
	turns._continue_after_active_unit_removed(true, false, false)
	await process_frame
	await process_frame
	await process_frame
	check(commands[0] == 1, "Duplicate pending removals issue exactly one player phase-end command")
	check(turns.current_phase == TurnManager.TurnPhase.ALLY_TURN and turns.active_unit == units[0], "A stale continuation cannot skip the first allied activation")
	turns.end_current_turn()
	check(commands[0] == 2 and turns.active_unit == units[1], "An explicit subsequent turn command advances exactly one ally")
	turns.queue_free()
	for unit in units: unit.queue_free()
	await process_frame
	await process_frame
	print("Removal continuation: %d failure(s)" % failures)
	quit(1 if failures else 0)
