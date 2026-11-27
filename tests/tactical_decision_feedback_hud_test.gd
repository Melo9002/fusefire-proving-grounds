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
	check(TacticalFeedbackText.shot(blocked).contains("Firing lane obstructed") and TacticalFeedbackText.shot(blocked, true).contains(str(blocker.grid_position)), "Blocked feedback identifies the real blocking cell")
	var trajectory := battle.shot_trajectory_visualizer
	check(not trajectory.debug_enabled, "Normal targeting does not require enabling debug trajectories")
	trajectory.draw_trajectory(CombatRules.get_shot_origin(actor, grid), blocked.aim_point, blocked.evaluation, true)
	check(trajectory.mesh_instance.mesh != null and trajectory.last_blocking_cell == blocker
		and trajectory.last_line_end.is_equal_approx(blocked.evaluation.blocking_point)
		and not trajectory.last_line_end.is_equal_approx(blocked.aim_point)
		and trajectory.blocker_marker.mesh is SphereMesh, "Normal targeting ends the line and marks its real contact")
	var original_raycaster := battle.mouse_raycaster
	var hover := HoverRaycaster.new()
	hover.hovered = enemy
	battle.mouse_raycaster = hover
	battle._update_attack_preview()
	check(trajectory.last_blocking_cell == blocker and battle._last_tactical_preview.contains("Firing lane obstructed"), "Idle hostile hover explains blocked shots even when Attack has no legal targets")
	battle.mouse_raycaster = original_raycaster
	hover.free()
	trajectory.set_debug_enabled(true)
	blocker.authored_shot_bounds = AABB(blocker.world_position + Vector3(-0.2, 0, -0.3), Vector3(0.4, 3, 0.6))
	trajectory.draw_trajectory(CombatRules.get_shot_origin(actor, grid), blocked.aim_point, blocked.evaluation, true)
	check(trajectory.blocker_marker.mesh.size.is_equal_approx(blocker.authored_shot_bounds.size) and trajectory.blocker_marker.position.is_equal_approx(blocker.authored_shot_bounds.get_center()), "Blocker marker honors sub-cell authored bounds")
	blocker.blocks_line_of_sight = false
	blocker.cover_type = MapCellData.CoverType.NONE
	blocker.cover_height = 0
	blocker.authored_shot_bounds = AABB()
	grid.map_data.rebuild_los_index()
	var clear := battle.query_attack(actor, enemy)
	check(clear.is_legal() and TacticalFeedbackText.shot(clear).contains("%d%% hit" % clear.hit_chance) and TacticalFeedbackText.shot(clear, true).contains("Range penalty") and TacticalFeedbackText.shot(clear, true).contains("Height"), "Shootable feedback reports authoritative chance and range/height contributions")
	var old_range := actor.attack_range
	actor.attack_range = 1 # Valid range shorter than this two-cell shot.
	check(TacticalFeedbackText.shot(battle.query_attack(actor, enemy)).contains("Out of range"), "Range and obstruction failures remain distinct")
	actor.attack_range = old_range

	var move := battle.query_move(actor, Vector3i(1, 0, 3))
	check(move.is_legal(), "Movement preview uses a real reachable destination")
	var fingerprint := BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager)
	var description := TacticalFeedbackText.movement(move, actor, [enemy], grid)
	check(description.contains("1 AP") and description.contains(String(enemy.tactical_id)) and description.contains("cover"), "Movement describes AP and directional cover against the actual enemy")
	check(fingerprint == BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager), "Preview never moves actors or changes authoritative state")
	blocker.cover_type = MapCellData.CoverType.LOW
	# At this diagonal, 0.6 lies below the lower-body ray. Use a real
	# protecting height so this remains an Aim-cancellation/cover preview case.
	blocker.cover_height = 0.8
	actor.tactical_state.establish_aim()
	var aimed_fingerprint := BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager)
	var proposed := CombatRules.evaluate_attack_from_cell(actor, move.target_cell, enemy, grid, actor.get_world_3d())
	check(proposed.is_legal and proposed.hit_chance == 80 and proposed.cover_penalty == 20, "Outgoing hypothetical shot uses physical low cover and excludes Aim canceled by movement")
	check(TacticalFeedbackText.movement(move, actor, [enemy], grid, true, true, true, true).contains("Your shot → %s: 80%% hit" % enemy.tactical_id), "Move hover describes an outgoing shot from the proposed cell")
	check(aimed_fingerprint == BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager), "Outgoing preview preserves Aim, AP, positions and occupancy")
	var remaining_ap := move.actor_ap_after
	move.actor_ap_after = 0
	check(TacticalFeedbackText.movement(move, actor, [enemy], grid).contains("No AP after moving"), "A geometrically clear shot is not promised when the move exhausts AP")
	move.actor_ap_after = remaining_ap
	actor.stats.consume_supply_points(actor.stats.current_supply_points)
	check(TacticalFeedbackText.movement(move, actor, [enemy], grid).contains("No SP"), "A clear hypothetical shot still reports missing Supply Points")
	check(not TacticalFeedbackText.movement(move, actor, [enemy], grid, false).contains("No SP"), "Historical SP-disabled battles do not acquire new resource restrictions")
	actor.stats.reload_supply_points()
	var committed_move := await battle.action_service.submit_move(battle.action_service.make_move_request(actor, move.target_cell, TacticalActionRequest.Source.PLAYER), true)
	var actual_after_move := battle.query_attack(actor, enemy)
	check(committed_move != null and not actor.tactical_state.is_aiming and actual_after_move.hit_chance == proposed.hit_chance and actual_after_move.obstruction == proposed.obstruction, "Actual Move then live Attack query matches the prior pure outgoing preview")

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
	await _check_depot_asymmetry()
	if OS.get_cmdline_user_args().has("capture"):
		await _capture_depot()
	print("Tactical decision feedback: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _place(unit: TacticalUnit, cell: Vector3i, grid: GridManager) -> void:
	grid.update_unit_position(unit, grid.get_unit_grid(unit), cell)
	unit.global_position = grid.grid_to_world(cell) + Vector3.UP * unit.standing_height

func _check_depot_asymmetry() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.SERVICE_DEPOT)
	config.battle_seed = 950507647
	config.player_count = 3
	config.enemy_count = 3
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 3)
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	await create_timer(0.2).timeout
	check(level.battle_initialization_succeeded, "Depot incident map initializes")
	if not level.battle_initialization_succeeded:
		level.queue_free()
		return
	var battle := level.battle_controller
	battle.set_process(false)
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	var grid := battle.grid_manager
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var enemy: TacticalUnit = level.turn_manager.enemy_units[2]
	var target_cell := Vector3i(17, 0, 15)
	_place(actor, Vector3i(16, 0, 15), grid)
	_place(enemy, Vector3i(22, 0, 22), grid)
	# The screenshots only establish Enemy 3's final cell. Test that exact lane.
	var start := battle.query_attack(actor, enemy)
	var move := battle.query_move(actor, target_cell)
	check(start.is_legal() and move.is_legal(), "A legal shot is lost when moving from the neighboring stop to the incident position")
	var revision := battle.action_service.state_revision
	var rng := battle.action_service.get_combat_rng_state()
	var opponents: Array[TacticalUnit] = [enemy]
	var options := TacticalFeedbackText.movement_options(move, actor, opponents, grid)
	check(options.size() == 1 and options[0].incoming.is_legal and options[0].outgoing.reason == "Blocked", "Arrival forecast evaluates both directions from the proposed offset")
	enemy.hide()
	check(TacticalFeedbackText.movement_options(move, actor, opponents, grid).is_empty(), "Hidden actors are excluded from public movement forecasts")
	enemy.show()
	battle.is_move_mode_active = true
	battle.update_unit_movement_zone()
	battle._update_movement_preview({"position": grid.grid_to_world(target_cell)})
	check(battle._last_tactical_preview.contains("Exposed to 1 with no clear return lane")
		and battle._last_tactical_preview.contains("0 out, 1 in")
		and battle.movement_ghost.destination == grid.grid_to_world(target_cell), "Actual hover warns before spending movement AP")
	check(revision == battle.action_service.state_revision and rng == battle.action_service.get_combat_rng_state() and actor.grid_position != target_cell, "Arrival advice is read-only")
	await _capture_asymmetry(level, actor, enemy, "arrival")
	check(battle._toggle_destination_inspection(), "Move hover can be pinned from the existing preview")
	battle._update_destination_inspection(enemy)
	check(battle._last_tactical_preview.contains("After moving · 2 AP remaining")
		and battle._last_tactical_preview.contains("Incoming lane")
		and battle._last_tactical_preview.contains("Cargo truck"), "Pinned inspection reads the selected enemy from the destination")
	check(battle.shot_trajectory_visualizer.destination_lines.size() == 1, "Pinned inspection isolates the selected hostile lane")
	await battle._on_floor_clicked(grid.grid_to_world(Vector3i(16, 0, 15)))
	check(revision == battle.action_service.state_revision and rng == battle.action_service.get_combat_rng_state()
		and actor.grid_position == Vector3i(16, 0, 15), "Inspecting an enemy and clicking another cell spends nothing")
	enemy.hide()
	battle._update_movement_preview({})
	check(not battle._last_tactical_preview.contains(String(enemy.tactical_id))
		and battle.shot_trajectory_visualizer.destination_lines.is_empty(), "Pinned preview drops a hidden target and its ray")
	enemy.show()
	battle.is_move_mode_active = false
	check(battle._pinned_destination == BattleController.NO_PREVIEW_CELL, "Cancel clears pinned inspection")
	check(await battle.try_move(actor, target_cell), "The real Move arrives at the forecast destination")
	var blocked := battle.query_attack(actor, enemy)
	var reverse := CombatRules.evaluate_attack(enemy, actor, grid, null)
	check(not blocked.is_legal() and reverse.is_legal, "Live queries preserve directional geometry after arrival")
	var before := battle.mouse_raycaster
	var hover := HoverRaycaster.new()
	hover.hovered = enemy
	battle.mouse_raycaster = hover
	battle._update_attack_preview()
	check(battle._last_tactical_preview.contains("Cargo truck blocks the firing lane")
		and battle._last_tactical_preview.contains("Exposed"), "Actual targeting names the truck and explains the one-way lane")
	var impact := battle.shot_trajectory_visualizer.last_line_end
	check(impact.is_equal_approx(blocked.evaluation.blocking_point) and absf(impact.x + 2.468994140625) < 0.002,
		"Preview terminates on the corrected cargo part, which still blocks Alpha")
	await _capture_asymmetry(level, actor, enemy, "blocked")
	var enemy_cell := grid.get_cell_data(enemy.grid_position)
	var enemy_stand := enemy_cell.world_position
	enemy_cell.world_position.z = 2.1
	var taper := CombatRules.evaluate_attack(enemy, actor, grid, null)
	var origin := CombatRules.get_shot_origin(enemy, grid)
	check(taper.is_legal and is_equal_approx(taper.visibility_fraction, 0.2)
		and CombatRules.get_blocking_cell(origin, taper.aim_point, grid) == null,
		"The measured waist-height ray beside the truck taper is legal")
	check(enemy.tactical_state.establish_overwatch(), "Set up a Guard forecast at the taper")
	var guard_forecast := battle.action_service.query_guard_reaction(enemy, actor)
	check(guard_forecast.can_fire and guard_forecast.evaluation.aim_point.is_equal_approx(taper.aim_point),
		"Guard and Attack use the same corrected taper lane")
	enemy.tactical_state.clear_overwatch()
	if DisplayServer.get_name() != "headless" and OS.get_cmdline_user_args().has("capture"):
		var old_visual := enemy.global_position
		enemy.global_position.z = origin.z
		battle._set_tactical_preview("Cargo taper check: the actual truck edge leaves this shoulder ray clear",
			TacticalFeedbackText.chance_color(taper.hit_chance))
		battle.shot_trajectory_visualizer.draw_trajectory(origin, taper.aim_point, taper, true)
		await _capture_asymmetry(level, actor, enemy, "taper-clear")
		enemy.global_position = old_visual
	var low_origin := Vector3(origin.x, 0.5, origin.z)
	var low_target := Vector3(taper.aim_point.x, 0.5, taper.aim_point.z)
	check(CombatRules.get_blocking_cell(low_origin, low_target, grid) != null,
		"The lower cargo overhang still blocks the same horizontal approach")
	enemy_cell.world_position.z = 1.5
	check(not CombatRules.evaluate_attack(enemy, actor, grid, null).is_legal, "A ray farther into the cargo remains blocked")
	enemy_cell.world_position = enemy_stand
	check(SurfaceNavigation.body_clear(grid.map_data, grid.grid_to_world(target_cell))
		and grid.grid_to_world(target_cell).is_equal_approx(Vector3(-2.8513, 0, -4.5)),
		"The shot parts preserve the same supported movement point")
	battle.mouse_raycaster = before
	hover.free()
	level.queue_free()
	await process_frame

func _capture_asymmetry(level: BattleLevel, actor: TacticalUnit, enemy: TacticalUnit, name: String) -> void:
	if not OS.get_cmdline_user_args().has("capture") or DisplayServer.get_name() == "headless": return
	var camera := level.get_node("CameraRig") as TacticalCamera
	camera.set_process(false)
	camera._cancel_selection_focus()
	var focus := (actor.global_position + enemy.global_position) * 0.5
	camera.camera.global_position = focus + Vector3(-10, 17, 10)
	camera.camera.look_at(focus)
	camera.camera.global_position -= camera.camera.global_basis.x * 1.4
	await process_frame
	await RenderingServer.frame_post_draw
	var output := "res://artifacts/intelligent-cover"
	DirAccess.make_dir_recursive_absolute(output)
	check(root.get_texture().get_image().save_png(output.path_join("depot-" + name + ".png")) == OK, "Captured incident preview " + name)

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
