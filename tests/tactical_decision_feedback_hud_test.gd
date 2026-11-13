extends SceneTree
## Contract: feedback reads the same tactical queries as execution and does not mutate them.

var failures := 0

class HoverRaycaster extends MouseRaycaster:
	var hovered: TacticalUnit
	func get_unit_under_mouse(_screen_position := Vector2.INF) -> TacticalUnit:
		return hovered

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(1, 1, false, 1, 0, Vector2i(32, 24), false, MissionActor.VIPBehavior.PLAYER_CONTROLLED, MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 1, false))
	root.add_child(level)
	await create_timer(0.2).timeout
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	var battle := level.battle_controller
	battle.set_process(false)
	var grid := battle.grid_manager
	var actor := level.turn_manager.player_units[0]
	var enemy := level.turn_manager.enemy_units[0]
	_place(actor, Vector3i(1, 0, 2), grid)
	_place(enemy, Vector3i(3, 0, 2), grid)
	var blocker := grid.get_cell_data(Vector3i(2, 0, 2))
	blocker.blocks_line_of_sight = true
	blocker.cover_height = 3.0
	blocker.cover_type = MapCellData.CoverType.FULL
	grid.map_data.rebuild_los_index()
	var blocked := battle.query_attack(actor, enemy)
	check(blocked.reason == "Blocked", "Actual authored tactical blocker rejects the shot")
	check(TacticalFeedbackText.shot(blocked).contains("highlighted") and TacticalFeedbackText.shot(blocked).contains(str(blocker.grid_position)), "Blocked feedback identifies the real blocking cell")
	var trajectory := battle.shot_trajectory_visualizer
	check(not trajectory.debug_enabled, "Normal targeting does not require enabling debug trajectories")
	trajectory.draw_trajectory(CombatRules.get_shot_origin(actor, grid), blocked.aim_point, blocked.evaluation, true)
	check(trajectory.mesh_instance.mesh != null and trajectory.last_blocking_cell == blocker, "Targeting shows a real blocker without debug enabled")
	var original_raycaster := battle.mouse_raycaster
	var hover := HoverRaycaster.new()
	hover.hovered = enemy
	battle.mouse_raycaster = hover
	battle._update_attack_preview()
	check(trajectory.last_blocking_cell == blocker and battle._last_tactical_preview.contains("Blocked"), "Idle hostile hover explains blocked shots even when Attack has no legal targets")
	battle.mouse_raycaster = original_raycaster
	hover.free()
	blocker.authored_shot_bounds = AABB(blocker.world_position + Vector3(-0.2, 0, -0.3), Vector3(0.4, 3, 0.6))
	trajectory.draw_trajectory(CombatRules.get_shot_origin(actor, grid), blocked.aim_point, blocked.evaluation, true)
	check(trajectory.blocker_marker.mesh.size.is_equal_approx(blocker.authored_shot_bounds.size) and trajectory.blocker_marker.position.is_equal_approx(blocker.authored_shot_bounds.get_center()), "Blocker marker honors sub-cell authored bounds")
	blocker.blocks_line_of_sight = false
	blocker.cover_type = MapCellData.CoverType.NONE
	blocker.cover_height = 0
	blocker.authored_shot_bounds = AABB()
	grid.map_data.rebuild_los_index()
	var clear := battle.query_attack(actor, enemy)
	check(clear.is_legal() and TacticalFeedbackText.shot(clear).contains("%d%% hit" % clear.hit_chance), "Shootable feedback reports the authoritative chance")
	var old_range := actor.attack_range
	actor.attack_range = 0
	check(TacticalFeedbackText.shot(battle.query_attack(actor, enemy)).contains("Out of range"), "Range and obstruction failures remain distinct")
	actor.attack_range = old_range

	var move := battle.query_move(actor, Vector3i(1, 0, 3))
	check(move.is_legal(), "Movement preview uses a real reachable destination")
	var fingerprint := BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager)
	var description := TacticalFeedbackText.movement(move, actor, [enemy], grid)
	check(description.contains("1 AP") and description.contains(String(enemy.tactical_id)) and description.contains("cover"), "Movement describes AP and directional cover against the actual enemy")
	check(fingerprint == BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager), "Preview never moves actors or changes authoritative state")

	var hud := level.get_node("Visualizers/BattleUI/ActionHUDController") as ActionHUDController
	check(hud.aim_button.tooltip_text.contains("immediately") and hud.aim_button.tooltip_text.contains("next activation"), "Aim explains cost and expiration before activation")
	check(hud.supply_points_label.tooltip_text.contains("Supply Points"), "SP has an explanation")
	check(hud.overwatch_button.tooltip_text.contains("all remaining AP") and hud.overwatch_button.tooltip_text.contains("-15"), "Guard explains activation cost and reaction accuracy before confirmation")
	battle._set_tactical_preview(description)
	check(hud._preview_label.visible and hud._preview_label.text == description, "Read-only preview reaches the real HUD")

	var result := await battle.action_service.submit_attack(battle.action_service.make_attack_request(actor, enemy, TacticalActionRequest.Source.PLAYER), true)
	check(result != null and not battle.combat_log.is_empty(), "An actual committed shot creates a combat-log entry")
	check(battle.combat_log[-1].contains(String(actor.tactical_id)) and battle.combat_log[-1].contains(String(enemy.tactical_id)), "Combat log identifies both participants")
	check(hud._combat_log_label.visible, "Actual battle displays the combat log")
	hud.hide()
	check(hud._combat_log_label.is_visible_in_tree(), "Combat log stays visible while AI turns hide action controls")
	hud.show()
	var reaction := OverwatchReactionEvent.new()
	reaction.watcher_id = enemy.tactical_id
	reaction.did_hit = true
	reaction.damage = 25
	result.reaction_events.append(reaction)
	var reaction_lines := TacticalFeedbackText.committed(result)
	check(reaction_lines[-1].begins_with("Guard: ") and reaction_lines[-1].contains("hit for 25"), "Guard reactions have a distinct damage explanation")
	for index in range(8): battle._on_action_committed(result)
	check(battle.combat_log.size() == 5, "Combat history remains bounded")

	var report := level.objective_manager.get_result_report()
	check(not report.contains("extracted") and report.contains("0/1"), "Eliminate results report mission progress without irrelevant extraction counters")
	var turn_hud := level.get_node("Visualizers/BattleUI/TurnHUDController") as TurnHUDController
	turn_hud.end_turn_button.text = "Enemies Acting"
	turn_hud._show_battle_result(TurnManager.BattleResult.DEFEAT)
	turn_hud._on_player_actions_exhausted()
	check(not turn_hud.end_turn_button.visible and turn_hud.turn_label.text.begins_with("DEFEAT"), "Terminal result hides the stale enemy-turn control")
	level.queue_free()
	await process_frame
	if OS.get_cmdline_user_args().has("capture"):
		await _capture_depot()
	print("Tactical decision feedback: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _place(unit: TacticalUnit, cell: Vector3i, grid: GridManager) -> void:
	grid.update_unit_position(unit, grid.get_unit_grid(unit), cell)
	unit.global_position = grid.grid_to_world(cell) + Vector3.UP * unit.standing_height

func _capture_depot() -> void:
	# A normal rendered seed, separate from the synthetic negative-case assertions above.
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(&"service_depot")
	config.battle_seed = 330397922
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 2, false)
	config.content_manifest = {"population_enabled": true}
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	await create_timer(0.2).timeout
	check(level.battle_initialization_succeeded, "Reported Service Depot seed initializes for inspection")
	if not level.battle_initialization_succeeded:
		level.queue_free()
		return
	var battle := level.battle_controller
	battle.set_process(false)
	var actor := level.turn_manager.player_units[0]
	var grid := battle.grid_manager
	var destination: Vector3i = battle.query_move(actor).legal_destination_cells[0]
	var move := battle.query_move(actor, destination)
	battle.path_visualizer.draw_path(move.path, Color(0, 0.5, 1, 0.4))
	battle._set_tactical_preview(TacticalFeedbackText.movement(move, actor, level.turn_manager.enemy_units, grid))
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://artifacts/tactical-decision-feedback.png") == OK, "Normal depot inspection capture saved")
	# Targeting inspection also works when the initial target is out of range.
	var enemy := level.turn_manager.enemy_units[0]
	var query := battle.query_attack(actor, enemy)
	battle.path_visualizer.clear_path()
	battle._set_tactical_preview(TacticalFeedbackText.shot(query))
	if query.evaluation:
		battle.shot_trajectory_visualizer.draw_trajectory(CombatRules.get_shot_origin(actor, grid), query.aim_point, query.evaluation, true)
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://artifacts/tactical-shot-feedback.png") == OK, "Depot shot inspection capture saved")
	level.queue_free()
	await process_frame
