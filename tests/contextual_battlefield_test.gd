extends "res://tests/contextual_firing_bay_test.gd"
## The authored Depot geometry is unchanged. Only the named rules variant and deployments differ.
const AI_START := Vector3i(17, 0, 22)
const DISCOVERED := Vector3i(16, 0, 22)
const OPPONENT := Vector3i(11, 0, 25)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and DisplayServer.get_name() != "headless":
		capture_dir = args[0]
		DirAccess.make_dir_recursive_absolute(capture_dir)
	var level := await _depot(BattlefieldCatalog.CONTEXTUAL_SHOWCASE, 16)
	if level.battle_initialization_succeeded:
		await _autonomous_move_and_shot(level)
	level.queue_free()
	await process_frame
	level = await _depot(BattlefieldCatalog.CONTEXTUAL_SHOWCASE, 16)
	if level.battle_initialization_succeeded:
		await _player_and_guard(level)
	level.queue_free()
	await process_frame
	level = await _depot(BattlefieldCatalog.CONTEXTUAL_FREIGHT, 16)
	if level.battle_initialization_succeeded:
		await _opposite_side(level)
	level.queue_free()
	await process_frame
	level = await _depot(BattlefieldCatalog.CONTEXTUAL_DEPOT, 950507647)
	if level.battle_initialization_succeeded:
		var grid := level.battle_controller.grid_manager
		var alpha: TacticalUnit = level.turn_manager.player_units[0]
		var hostile: TacticalUnit = level.turn_manager.enemy_units[0]
		_place(alpha, Vector3i(17, 0, 15), grid)
		_place(hostile, Vector3i(22, 0, 22), grid)
		check(not level.battle_controller.query_attack(alpha, hostile).is_legal()
			and CombatRules.evaluate_attack(hostile, alpha, grid, null).is_legal,
			"Enabling discovery does not force a shot through Alpha's truck")
	level.queue_free()
	await process_frame
	print("Contextual battlefield: %d checks, %d failure(s), %d muzzle samples" % [checks, failures, muzzle_samples])
	quit(int(failures > 0))

func _depot(site: StringName, seed_value: int) -> BattleLevel:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.battle_seed = seed_value
	config.select_battlefield(site)
	config.player_count = 1
	config.enemy_count = 1
	config.difficulty = AIDifficultyPolicy.Tier.HARD
	config.enemy_commander = AICommanderPolicy.Profile.CAUTIOUS
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 1)
	var level := Scene.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	for frame in 6: await process_frame
	check(level.battle_initialization_succeeded, "Authored contextual map initializes")
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	return level

func _place(actor: TacticalUnit, cell: Vector3i, grid: GridManager) -> void:
	grid.update_unit_position(actor, actor.grid_position, cell)
	actor.global_position = grid.grid_to_world(cell) + Vector3.UP * actor.standing_height

func _autonomous_move_and_shot(level: BattleLevel) -> void:
	var battle := level.battle_controller
	var grid := battle.grid_manager
	var shooter: TacticalUnit = level.turn_manager.enemy_units[0]
	var target: TacticalUnit = level.turn_manager.player_units[0]
	check(shooter.grid_position == AI_START and target.grid_position == OPPONENT
		and not battle.query_attack(shooter, target).is_legal(), "Known enemy starts with no legal shot")
	var forecast := CombatRules.evaluate_attack_from_cell(shooter, DISCOVERED, target, grid, null)
	check(forecast.is_legal and forecast.firing_solution.body_offset != Vector3.ZERO, "Ordinary position evaluation sees the unmarked contextual stop")
	if not forecast.is_legal: return
	shooter.visual_adapter.presenter.attack.shot_released.connect(_observe(shooter, forecast.firing_solution, "depot-ai"), CONNECT_ONE_SHOT)
	var moves: Array[MoveActionResult] = []
	var attacks: Array[AttackActionResult] = []
	battle.action_service.action_presented.connect(func(result):
		if result.request.actor_id != shooter.tactical_id: return
		if result is MoveActionResult: moves.append(result)
		if result is AttackActionResult: attacks.append(result))
	level.turn_manager.end_current_turn()
	var deadline := Time.get_ticks_msec() + 15000
	while attacks.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	var chosen := not moves.is_empty() and not attacks.is_empty() and moves[0].target_cell == DISCOVERED
	check(chosen and attacks[0].request.source == TacticalActionRequest.Source.AI
		and attacks[0].firing_solution.to_replay_record() == forecast.firing_solution.to_replay_record(),
		"Cautious AI moves from the blocked tile and independently commits the forecast contextual shot")
	if not chosen: return
	var recording: BattleReplayRecording = level._replay_recorder.recording
	var path := "user://contextual-depot-%d.replay.json" % OS.get_process_id()
	check(recording.save_json(path) == OK, "Save real AI Move + Attack sequence")
	var loaded := BattleReplayRecording.load_json(path)
	var copy := Scene.instantiate() as BattleLevel
	copy.configure_replay(loaded)
	root.add_child(copy)
	if copy.battle_initialization_succeeded:
		var player := copy.get_node("BattleReplayPlayer") as BattleReplayPlayer
		player.set_playback_speed(4)
		deadline = Time.get_ticks_msec() + 16000
		while not player.playback_complete and Time.get_ticks_msec() < deadline: await process_frame
		check(player.playback_succeeded and player.verified_actions == loaded.actions.size(),
			"Versioned authored deployment replays the actual actions and firing solution: " + player.last_divergence)
	else:
		check(false, "The authored replay scene reconstructs")
	copy.queue_free()
	await process_frame
	DirAccess.remove_absolute(path)

func _player_and_guard(level: BattleLevel) -> void:
	var battle := level.battle_controller
	var grid := battle.grid_manager
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var enemy: TacticalUnit = level.turn_manager.enemy_units[0]
	_place(actor, AI_START, grid)
	_place(enemy, OPPONENT, grid)
	var move := battle.query_move(actor, DISCOVERED)
	var preview := TacticalFeedbackText.movement(move, actor, [enemy], grid)
	check(move.is_legal() and preview.contains("Side-step shot available"), "Ordinary hover predicts the discovered shot for the other faction")
	check(await battle.try_move(actor, DISCOVERED), "Player reaches the same position through authority")
	var query := battle.query_attack(actor, enemy)
	check(query.is_legal() and TacticalFeedbackText.shot(query).contains("Side-step shot"), "Player targeting names the same outgoing posture")
	if not query.is_legal(): return
	_compatibility_and_clearance(battle, actor, enemy)
	await _sliced_overlay(battle, actor)
	var visual := actor.visual_adapter.position
	actor.visual_adapter.presenter.attack.shot_released.connect(_observe(actor, query.evaluation.firing_solution, "depot-player"), CONNECT_ONE_SHOT)
	check(await battle.try_attack(actor, enemy), "Player fires through ordinary Attack")
	check(actor.grid_position == DISCOVERED and actor.visual_adapter.position.is_equal_approx(visual), "Actor returns to canonical position")
	# A second surveyed lane has an incoming legal attack, so the standard
	# retaliation trigger can demonstrate Guard without inventing a trigger.
	_place(actor, Vector3i(23, 0, 15), grid)
	_place(enemy, Vector3i(30, 0, 15), grid)
	battle._shot_cell_cache.clear()
	battle.toggle_overwatch_mode()
	var overlay_deadline := Time.get_ticks_msec() + 4000
	while battle.overwatch_range_visualizer.preview_cells.is_empty() and Time.get_ticks_msec() < overlay_deadline:
		await process_frame
	check(battle.overwatch_range_visualizer.preview_cells.has(enemy.grid_position), "Guard's sliced preview includes the validated contextual lane")
	battle.toggle_overwatch_mode()
	var arm := await battle.action_service.submit_overwatch(battle.action_service.make_overwatch_request(actor, TacticalActionRequest.Source.PLAYER), true)
	check(arm != null, "Reserve the remaining AP for Guard")
	if arm == null: return
	var reaction := battle.action_service.query_guard_reaction(actor, enemy)
	check(reaction.can_fire and reaction.evaluation.firing_solution.body_offset != Vector3.ZERO, "Guard finds the surveyed shot through shared evaluation")
	if not reaction.can_fire: return
	var steps := grid.map_data.contextual_discovery_enabled
	grid.map_data.contextual_discovery_enabled = false
	check(not battle.action_service.query_guard_reaction(actor, enemy).can_fire and actor.tactical_state.is_overwatching, "Blocked normal shot leaves reaction reserved")
	grid.map_data.contextual_discovery_enabled = steps
	actor.visual_adapter.presenter.attack.shot_released.connect(_observe(actor, reaction.evaluation.firing_solution, "depot-guard"), CONNECT_ONE_SHOT)
	level.turn_manager.current_phase = TurnManager.TurnPhase.ENEMY_TURN
	level.turn_manager.active_unit = enemy
	var action := await battle.action_service.submit_attack(battle.action_service.make_attack_request(enemy, actor, TacticalActionRequest.Source.AI))
	check(action != null and action.reaction_events.size() == 1
		and action.reaction_events[0].firing_solution.to_replay_record() == reaction.evaluation.firing_solution.to_replay_record(),
		"Existing retaliation orders and presents one contextual reaction")

func _compatibility_and_clearance(battle: BattleController, actor: TacticalUnit, enemy: TacticalUnit) -> void:
	var grid := battle.grid_manager
	var original := actor.visual_adapter
	var small := preload("res://art/characters/small_mira_0/runtime/small_mira_0_unit_visual.tscn").instantiate() as TacticalCharacterAdapter
	actor.add_child(small)
	actor.visual_adapter = small
	var rejected := battle.query_attack(actor, enemy)
	check(not rejected.is_legal() and rejected.evaluation.contextual_rejection.contains("Uncertified"), "Small MIRA cannot use the standard rig's offset")
	var direct := CombatRules.evaluate_attack_from_cell(actor, OPPONENT + Vector3i.BACK, enemy, grid, null)
	check(direct.is_legal and direct.firing_solution.body_offset == Vector3.ZERO, "An incompatible rig retains ordinary firing")
	actor.visual_adapter = original
	small.free()
	var rifle := original.rig.weapon_scene
	original.rig.weapon_scene = null
	check(not battle.query_attack(actor, enemy).is_legal(), "Missing calibrated weapon rejects contextual firing")
	original.rig.weapon_scene = rifle

	var neighbor_cell := DISCOVERED + Vector3i.FORWARD
	var neighbor := grid.get_cell_data(neighbor_cell)
	check(neighbor != null and neighbor.can_stop and grid.get_unit_at(neighbor_cell) == null, "Neighbor can occupy a real supported tile")
	check(battle._legal_shot_cells(actor).has(enemy.grid_position), "Coverage initially includes the contextual lane")
	var blocker := TacticalUnit.new()
	blocker.grid_position = neighbor_cell
	grid.occupancy_map[neighbor_cell] = blocker
	var blocked := battle.query_attack(actor, enemy)
	check(not blocked.is_legal(), "A nearby body prevents the generalized transition")
	check(not battle._legal_shot_cells(actor).has(enemy.grid_position), "Same-height blocker invalidates display coverage")
	grid.occupancy_map.erase(neighbor_cell)
	blocker.free()
	check(battle._legal_shot_cells(actor).has(enemy.grid_position), "Coverage returns when the blocker leaves")

func _opposite_side(level: BattleLevel) -> void:
	var battle := level.battle_controller
	var grid := battle.grid_manager
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var enemy: TacticalUnit = level.turn_manager.enemy_units[0]
	_place(actor, Vector3i(3, 0, 13), grid)
	_place(enemy, Vector3i(10, 0, 13), grid)
	var query := battle.query_attack(actor, enemy)
	check(query.is_legal() and query.evaluation.firing_solution.body_offset.z < -0.24,
		"Freight Yard's opposite-side adjustment clears a different authored obstacle")
	if not query.is_legal(): return
	var target_cell := grid.get_cell_data(enemy.grid_position)
	var rest := target_cell.world_position
	target_cell.world_position.y += 0.5
	var details := {}
	check(CombatRules._contextual_step(actor, actor.grid_position, enemy, enemy.grid_position, grid, details) == null
		and str(details.get("reason", "")).contains("aim cone"), "Cross-height side step is outside the certified pose")
	target_cell.world_position = rest
	actor.visual_adapter.presenter.attack.shot_released.connect(_observe(actor, query.evaluation.firing_solution, "freight-opposite"), CONNECT_ONE_SHOT)
	check(await battle.try_attack(actor, enemy), "Opposite-side attack executes and returns in an authored battle")

func _sliced_overlay(battle: BattleController, actor: TacticalUnit) -> void:
	var expected := battle._legal_shot_cells(actor)
	battle._shot_cell_cache.clear()
	battle.toggle_attack_mode()
	check(battle.is_attack_mode_active and battle.current_attack_zone.is_empty(), "Cold contextual coverage does not complete in the input frame")
	battle.toggle_attack_mode()
	for frame in 4: await process_frame
	check(battle.current_attack_zone.is_empty(), "A closed Attack overlay discards suspended coverage")
	battle.toggle_attack_mode()
	var deadline := Time.get_ticks_msec() + 4000
	while battle.current_attack_zone.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	check(battle.current_attack_zone == expected, "Completed sliced overlay matches the synchronous geometric coverage")
	battle.toggle_attack_mode()
