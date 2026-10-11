extends SceneTree

var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var level = load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(3, 1)
	root.add_child(level)
	await create_timer(0.15).timeout

	var turns = level.turn_manager
	var battle = level.battle_controller
	var bar = level.get_node("Visualizers/BattleUI/UnitPortraitBar") as UnitPortraitBar
	var selection_visualizer = level.get_node("Visualizers/UnitSelectionVisualizer") as UnitSelectionVisualizer
	var first_mesh = turns.player_units[0].get_node("MeshInstance3D") as MeshInstance3D
	check(bar.portraits.size() == 3, "Portrait count matches the player roster")
	check(bar.portraits[0].display_state == UnitPortrait.DisplayState.SELECTED, "Initial active unit is highlighted")
	check(selection_visualizer.selected_unit == turns.player_units[0], "Initial active unit owns the world outline")
	check(first_mesh.material_overlay != null, "Selected unit mesh renders an outline")

	bar.portraits[1]._on_pressed()
	check(turns.active_unit == turns.player_units[1], "Clicking a portrait selects its unit")
	check(bar.portraits[1].display_state == UnitPortrait.DisplayState.SELECTED, "Portrait click updates selected state")
	check(first_mesh.material_overlay == null, "Previous unit outline is cleared")
	check(selection_visualizer.selected_unit == turns.player_units[1], "Portrait selection moves the world outline")

	battle._on_unit_clicked(turns.player_units[2])
	check(bar.portraits[2].display_state == UnitPortrait.DisplayState.SELECTED, "Battlefield selection updates the portrait")
	check(bar.portraits[1].display_state == UnitPortrait.DisplayState.READY, "Previous portrait returns to ready")
	check(selection_visualizer.selected_unit == turns.player_units[2], "Battlefield selection moves the world outline")

	var moving_unit = turns.player_units[2]
	moving_unit.stats.consume_ap(1)
	var grid = level.get_node("Systems/GridManager") as GridManager
	var start_cell = grid.world_to_grid(moving_unit.global_position)
	var destination = start_cell + Vector3i(1, 0, 0)
	battle.try_move(moving_unit, destination)
	check(turns.active_unit == moving_unit, "Final movement keeps selection until arrival")
	await moving_unit.movement_finished
	# Selection advances only after the blocking traversal/action-camera
	# presentation releases the authoritative action barrier.
	while battle.is_action_in_progress:
		await process_frame
	check(bar.portraits[2].display_state == UnitPortrait.DisplayState.EXHAUSTED, "Zero AP shows exhausted state")
	check(bar.portraits[2].disabled, "Exhausted portrait cannot request selection")
	check(turns.active_unit == turns.player_units[0], "Zero AP cycles to the next available unit")
	check(bar.portraits[0].display_state == UnitPortrait.DisplayState.SELECTED, "Cycling updates portrait selection")
	check(selection_visualizer.selected_unit == turns.player_units[0], "Cycling updates the world outline")

	turns.player_units[0].stats.consume_ap(2)
	await process_frame
	check(turns.active_unit == turns.player_units[1], "Cycling skips the exhausted unit")
	turns.player_units[1].stats.consume_ap(2)
	await process_frame
	var end_turn_button = level.get_node("Visualizers/BattleUI/TurnHUDController/VBoxContainer/EndTurnButton") as Button
	check(turns.active_unit == turns.player_units[1], "No available unit leaves selection for inspection")
	check(end_turn_button.text == "END TURN — NO AP", "End Turn becomes prominent when all units are exhausted")

	var defeated_unit = turns.player_units[1]
	defeated_unit.stats.take_damage(1000)
	await process_frame
	check(bar.portraits.size() == 3, "Defeated unit keeps its portrait for battle history")
	check(bar.portraits[1].display_state == UnitPortrait.DisplayState.DEAD, "Defeated portrait shows dead state")
	check(bar.portraits[1].hp_label.text == "HP  0 / 100", "Portrait HP updates before removal")
	check(turns.player_units.size() == 2, "Defeat still removes the world unit from the roster")

	level.queue_free()
	await process_frame
	print("Portrait bar smoke: %d failure(s)" % failures)
	quit(1 if failures else 0)
