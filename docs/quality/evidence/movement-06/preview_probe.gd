extends "res://tests/surface_curved_battle_test.gd"
## Feed a known floor hit through the real movement hover/click handlers during
## the curved Depot battle. The mouse raycaster itself is outside this probe.

func _capture(level: BattleLevel, point: Vector3, label: String) -> void:
	if label == "depot-before-move":
		var battle := level.battle_controller
		var grid := battle.grid_manager
		var actor := battle.tactical_unit
		var valid_cell := grid.world_to_grid(point)
		var blocked_cell := grid.world_to_grid(grid.map_data.curved_parts[0].center)
		var valid := battle.query_move(actor, valid_cell)
		var blocked := battle.query_move(actor, blocked_cell)
		var blocked_world := grid.get_cell_data(blocked_cell).support_center
		var revision := battle.action_service.state_revision
		var ap_before := actor.stats.current_ap
		battle.is_move_mode_active = true
		battle.update_unit_movement_zone()
		battle._update_movement_preview({"position": point})
		var positive_feedback := battle._last_tactical_preview
		battle._update_movement_preview({"position": blocked_world})
		var blocked_feedback := battle._last_tactical_preview
		await battle._on_floor_clicked(blocked_world)
		check(valid.is_legal() and not positive_feedback.is_empty(), "Known valid stop is previewed")
		check(not blocked.is_legal(), "Known tank center is rejected")
		check(revision == battle.action_service.state_revision and ap_before == actor.stats.current_ap, "Rejected click spends no AP and changes no revision")
		print("[Preview] actor=", actor.tactical_id, " origin=", actor.grid_position, " valid=", valid_cell, " positive=", not positive_feedback.is_empty(), " blocked=", blocked_cell, " authority_code=", blocked.validation.code, " hover_feedback=", JSON.stringify(blocked_feedback), " after_click=", JSON.stringify(battle._last_tactical_preview))
		battle.is_move_mode_active = false
	if label == "depot-around-tank" and DisplayServer.get_name() != "headless":
		var debug := level.get_node("Visualizers/BattleUI/DebugTools") as DebugTools
		debug.set_panel_open(true)
		debug._tabs.current_tab = 4
		debug._walkability_toggle.button_pressed = true
		debug.set_panel_open(false)
		await super._capture(level, point, "depot-f3-walkability")
		debug._walkability_toggle.button_pressed = false
	await super._capture(level, point, label)
