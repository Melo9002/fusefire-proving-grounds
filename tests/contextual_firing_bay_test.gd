extends SceneTree
## The standard Attack, Guard, AI and replay paths share one opted-in firing bay.
const Scene := preload("res://levels/prototype_map/prototype_map.tscn")
var failures := 0
var checks := 0
var muzzle_samples := 0
var capture_dir := ""

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(text)

func _level(seed_value: int) -> BattleLevel:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.CONTEXTUAL_BAY)
	config.battle_seed = seed_value
	config.player_count = 1
	config.enemy_count = 1
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 1)
	var level := Scene.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	for frame in 6: await process_frame
	check(level.battle_initialization_succeeded, "Reference battle initializes")
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	return level

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and DisplayServer.get_name() != "headless":
		capture_dir = args[0]
		DirAccess.make_dir_recursive_absolute(capture_dir)
	for seed_value in [1, 3]:
		var battle := await _level(seed_value)
		if battle.battle_initialization_succeeded: await _player_attack(battle, seed_value)
		battle.queue_free()
		await process_frame
	await _guard()
	await _ai()
	print("Contextual firing bay: %d checks, %d failure(s), %d rendered muzzle samples" % [checks, failures, muzzle_samples])
	quit(0 if failures == 0 else 1)

func _player_attack(level: BattleLevel, seed_value: int) -> void:
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var enemy: TacticalUnit = level.turn_manager.enemy_units[0]
	var battle := level.battle_controller
	var grid := battle.grid_manager
	var query := battle.query_attack(actor, enemy)
	check(query.is_legal() and query.evaluation.firing_solution and query.evaluation.firing_solution.body_offset.length() > 0.23, "Blocked center lane resolves to a same-cell side step")
	if not query.is_legal(): return
	var solution := query.evaluation.firing_solution
	check(TacticalFeedbackText.shot(query).contains("Side-step shot"), "Targeting tells the player which shot will execute")
	var tile := actor.grid_position
	var original_root := actor.global_position
	var original_adapter := actor.visual_adapter.position
	var before_rng := battle.action_service.get_combat_rng_state()
	check(battle.query_attack(actor, enemy).evaluation.firing_solution.to_replay_record() == solution.to_replay_record()
		and before_rng == battle.action_service.get_combat_rng_state(), "Repeated geometry selection is deterministic and read-only")
	var offset: Vector3 = grid.map_data.contextual_steps[tile]
	grid.map_data.contextual_steps[tile] = offset.normalized() * 0.31
	check(not battle.query_attack(actor, enemy).is_legal(), "Excessive adjustment does not authorize a shot")
	grid.map_data.contextual_steps[tile] = offset
	# Body obstruction and a weapon-only obstacle each keep a nominal open firing
	# ray from creating a legal shot. No occupancy or canonical point is moved.
	var from := grid.grid_to_world(tile)
	var positive_x := offset.x > 0
	var solid_x := 0.43 if positive_x else -0.53
	var body_block := AABB(from + Vector3(solid_x, 0, -0.1), Vector3(0.1, 1.0, 0.2))
	var weapon_block := AABB(from + Vector3(-0.2, 1.20, 0.53 if positive_x else -0.63), Vector3(0.4, 0.3, 0.10))
	for part in [body_block, weapon_block]:
		grid.map_data.movement_parts.append(part)
		SurfaceNavigation._rebuild_movement_index(grid.map_data)
		check(not battle.query_attack(actor, enemy).is_legal(), "Obstructed body or weapon transition rejects candidate")
		grid.map_data.movement_parts.erase(part)
		SurfaceNavigation._rebuild_movement_index(grid.map_data)
	if seed_value == 1:
		var neighbor_tile := tile + Vector3i.RIGHT
		var neighbor := grid.get_cell_data(neighbor_tile)
		var old_stand := neighbor.world_position
		var original_enemy := enemy.grid_position
		var real_target := grid.get_cell_data(original_enemy)
		# Use a temporary additional body registry entry as a controlled negative.
		var blocker := TacticalUnit.new()
		grid.occupancy_map[neighbor_tile] = blocker
		blocker.grid_position = neighbor_tile
		neighbor.world_position = from + Vector3.RIGHT * 0.71
		check(not battle.query_attack(actor, enemy).is_legal() and real_target.world_position != neighbor.world_position, "Another body prevents the same local adjustment")
		grid.occupancy_map.erase(neighbor_tile)
		neighbor.world_position = old_stand
		blocker.free()
		var previous := tile + Vector3i(0, 0, -1)
		grid.update_unit_position(actor, tile, previous)
		var move := battle.query_move(actor, tile)
		var enemies: Array[TacticalUnit] = [enemy]
		var forecast := TacticalFeedbackText.movement(move, actor, enemies, grid)
		check(move.is_legal() and forecast.contains("Side-step shot available"), "Move preview predicts contextual firing from the actual destination")
		grid.update_unit_position(actor, previous, tile)
	var observer := _observe(actor, solution, "player-%d" % seed_value)
	actor.visual_adapter.presenter.attack.shot_released.connect(observer)
	var committed := await battle.try_attack(actor, enemy)
	actor.visual_adapter.presenter.attack.shot_released.disconnect(observer)
	check(committed and actor.stats.current_ap == 2 and actor.stats.current_supply_points == 3, "Contextual Attack spends ordinary AP and SP")
	check(actor.grid_position == tile and actor.global_position.is_equal_approx(original_root) and actor.visual_adapter.position.is_equal_approx(original_adapter), "Contextual action returns without moving tactical occupancy")
	var recording: BattleReplayRecording = level._replay_recorder.recording
	check(recording.actions.size() == 1 and recording.actions[0].resolved.firing_solution == solution.to_replay_record(), "Committed receipt records the previewed posture")
	if seed_value == 1 and recording.actions.size() == 1: await _replay(recording)

func _observe(actor: TacticalUnit, solution: CombatRules.FiringSolution, label: String) -> Callable:
	return func(_timeline):
		var muzzle := actor.visual_adapter.rig.muzzle_socket
		var error := muzzle.global_position.distance_to(solution.origin)
		var angle := rad_to_deg(muzzle.global_basis.z.angle_to(solution.aim_point() - muzzle.global_position))
		print("[ContextualMuzzle] ", label, " error_m=", error, " angle_deg=", angle)
		muzzle_samples += 1
		check(error <= 0.02 and angle <= 2.5, "Shown muzzle agrees with resolved firing solution in " + label)
		check(CombatRules.get_blocking_cell(muzzle.global_position, solution.aim_point(), actor.visual_adapter.presentation_grid) == null, "Rendered muzzle path clears the reference obstacle")
		if not capture_dir.is_empty(): _capture_after_draw(actor, label)

func _capture_after_draw(actor: TacticalUnit, label: String) -> void:
	var camera := actor.get_tree().root.get_camera_3d()
	if camera:
		var rig := camera.get_parent() as TacticalCamera
		if rig:
			rig.set_process(false)
			rig._environment_apertures.restore_view()
			rig._restore_faded_occluders({})
		for visual in get_nodes_in_group(TacticalCameraAperture.GROUP):
			visual.restore_view()
		var side := -1.0 if label == "player-3" else 1.0
		var focus := actor.global_position + Vector3(0, 0.0, 1.9 * side)
		camera.global_position = focus + Vector3(5.3 * side, 4.9, -4.1 * side)
		camera.look_at(focus)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_dir.path_join(label + ".png"))

func _replay(recording: BattleReplayRecording) -> void:
	var path := "res://.godot/contextual-bay-test.replay.json"
	check(recording.save_json(path) == OK, "Save actual contextual action")
	var loaded := BattleReplayRecording.load_json(path)
	check(loaded.is_playable(), "Recorded contextual battle validates")
	var copy := Scene.instantiate() as BattleLevel
	copy.configure_replay(loaded)
	root.add_child(copy)
	if copy.battle_initialization_succeeded:
		var player := copy.get_node("BattleReplayPlayer") as BattleReplayPlayer
		player.set_playback_speed(4)
		var limit := Time.get_ticks_msec() + 8000
		while not player.playback_complete and Time.get_ticks_msec() < limit: await process_frame
		check(player.playback_succeeded and player.verified_actions == 1, "Replay verifies the complete committed posture and action " + player.last_divergence)
	else:
		check(false, "Compiled replay scene initializes")
	copy.queue_free()
	await process_frame
	DirAccess.remove_absolute(path)

func _guard() -> void:
	var level := await _level(1)
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var enemy: TacticalUnit = level.turn_manager.enemy_units[0]
	var service := level.battle_controller.action_service
	var arm := await service.submit_overwatch(service.make_overwatch_request(actor, TacticalActionRequest.Source.PLAYER), true)
	check(arm != null, "Player reserves Guard from the bay")
	var stops := level.battle_controller.grid_manager.map_data.contextual_steps
	var saved: Vector3 = stops[actor.grid_position]
	stops[actor.grid_position] = saved.normalized() * 0.31
	var denied := service.query_guard_reaction(actor, enemy)
	check(not denied.can_fire and denied.reason == "Blocked" and actor.tactical_state.is_overwatching,
		"An invalid contextual shift leaves Guard reserved")
	stops[actor.grid_position] = saved
	var chance := service.query_guard_reaction(actor, enemy)
	check(chance.can_fire and chance.evaluation.firing_solution.body_offset.length() > 0.23, "Guard accepts the same physically valid contextual solution")
	if chance.can_fire:
		var observer := _observe(actor, chance.evaluation.firing_solution, "guard")
		actor.visual_adapter.presenter.attack.shot_released.connect(observer)
		level.turn_manager.current_phase = TurnManager.TurnPhase.ENEMY_TURN
		level.turn_manager.active_unit = enemy
		var hit := await service.submit_attack(service.make_attack_request(enemy, actor, TacticalActionRequest.Source.AI))
		check(hit != null and hit.reaction_events.size() == 1 and hit.reaction_events[0].firing_solution.to_replay_record() == chance.evaluation.firing_solution.to_replay_record(), "Actual Guard attaches contextual firing to the parent Attack receipt")
		if is_instance_valid(actor): actor.visual_adapter.presenter.attack.shot_released.disconnect(observer)
	level.queue_free()
	await process_frame

func _ai() -> void:
	var level := await _level(2)
	var shooter: TacticalUnit = level.turn_manager.enemy_units[0]
	var target: TacticalUnit = level.turn_manager.player_units[0]
	var expected := CombatRules.evaluate_attack(shooter, target, level.battle_controller.grid_manager, null)
	check(expected.is_legal and expected.firing_solution.body_offset.length() > 0.23, "Faction-swapped geometry remains a contextual attack")
	if not expected.is_legal:
		level.queue_free()
		await process_frame
		return
	var observer := _observe(shooter, expected.firing_solution, "ai")
	shooter.visual_adapter.presenter.attack.shot_released.connect(observer, CONNECT_ONE_SHOT)
	var receipts := []
	level.battle_controller.action_service.action_presented.connect(func(result):
		if result is AttackActionResult and result.request.actor_id == shooter.tactical_id: receipts.append(result))
	level.turn_manager.end_current_turn()
	var deadline := Time.get_ticks_msec() + 10000
	while receipts.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	check(not receipts.is_empty() and receipts[0].request.source == TacticalActionRequest.Source.AI
		and receipts[0].firing_solution.to_replay_record() == expected.firing_solution.to_replay_record(), "Autonomous enemy chooses and presents a contextual Attack after normal handoff")
	level.queue_free()
	await process_frame
