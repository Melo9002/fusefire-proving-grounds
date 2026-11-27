extends "res://tests/rescue_carrier_loss_test.gd"

const ORIGIN := Vector3i(13, 4, 1)
const CHECKPOINT := Vector3i(13, 4, 2)
const DESTINATION := Vector3i(13, 4, 3)
const ESCORT := Vector3i(14, 4, 2)
enum Case { CHECKPOINT, FALLBACK, ARCHIVE, LOST, SURVIVES }
var capture_dir := ""

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "capture" and DisplayServer.get_name() != "headless":
		capture_dir = args[1]
		DirAccess.make_dir_recursive_absolute(capture_dir)
		await _check_reactive_move(Case.CHECKPOINT)
	else:
		for scenario in [Case.CHECKPOINT, Case.FALLBACK, Case.ARCHIVE, Case.LOST, Case.SURVIVES]:
			await _check_reactive_move(scenario)
	print("Reactive passenger release: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _prepare(level: BattleLevel, scenario: Case) -> void:
	var battle := level.battle_controller
	var grid := battle.grid_manager
	var service := battle.action_service
	var carrier: TacticalUnit = level.turn_manager.player_units[0]
	var watcher: TacticalUnit = level.turn_manager.enemy_units[0]
	# Certify the trigger independently of the authored room's cover and shot RNG.
	for cell: MapCellData in grid.map_data.cells.values():
		cell.blocks_line_of_sight = false
		cell.cover_type = MapCellData.CoverType.NONE
		cell.cover_height = 0
	grid.map_data.rebuild_los_index()
	for pair in [[carrier, ORIGIN], [level.turn_manager.player_units[1], ESCORT]]:
		var unit: TacticalUnit = pair[0]
		var location: Vector3i = pair[1]
		check(grid.can_unit_occupy_cell(unit, location), "Fixture unit has a legal standing cell")
		grid.update_unit_position(unit, unit.grid_position, location)
		unit.global_position = grid.grid_to_world(location) + Vector3.UP * unit.standing_height
	if scenario != Case.SURVIVES:
		carrier.stats.current_hp = 1
	for enemy: TacticalUnit in level.turn_manager.enemy_units:
		enemy.attack_range = 100
		check(enemy.tactical_state.establish_overwatch(), "Watcher reserves a reaction")
	if scenario == Case.FALLBACK:
		for x in range(-1, 2):
			for z in range(-1, 2):
				var location := CHECKPOINT + Vector3i(x, 0, z)
				var cell := grid.get_cell_data(location)
				if cell and location not in [ORIGIN, DESTINATION, ESCORT]:
					cell.can_stop = false
	if scenario == Case.LOST:
		# Keep Move legal at submission, then model no available stop at defeat.
		battle.unit_defeated_in_battle.connect(func(_unit: TacticalUnit):
			for x in range(-3, 4):
				for z in range(-3, 4):
					var cell := grid.get_cell_data(CHECKPOINT + Vector3i(x, 0, z))
					if cell: cell.can_stop = false, CONNECT_ONE_SHOT)
	var opportunity := service.query_guard_reaction(watcher, carrier, CHECKPOINT)
	check(opportunity.get("can_fire", false), "Guard is legal at the checkpoint")
	if not opportunity.get("can_fire", false):
		return
	var rng := RandomNumberGenerator.new()
	for seed_value in 1000:
		rng.seed = seed_value
		if AttackActionResult.roll_hits(rng.randf() * 100.0, opportunity.evaluation.hit_chance):
			service._combat_rng.seed = seed_value
			break

func _check_reactive_move(scenario: Case) -> void:
	var level := await _create_level()
	var grid := level.battle_controller.grid_manager
	var service := level.battle_controller.action_service
	var carrier: TacticalUnit = level.turn_manager.player_units[0]
	var escort: TacticalUnit = level.turn_manager.player_units[1]
	var second_watcher: TacticalUnit = level.turn_manager.enemy_units[1]
	var vip := level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	var mission_id := vip.get_mission_id()
	_prepare(level, scenario)
	var record: BattleReplayRecording = level._replay_recorder.recording
	record.initial_state_fingerprint = BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager)
	if scenario == Case.ARCHIVE:
		service.checkpoint_passenger_release = false
	check(await level.objective_manager.try_rescue(carrier, vip), "Production Rescue picks up the VIP")
	var preview := service.query_move(carrier.tactical_id, DESTINATION)
	if not preview.is_legal() or preview.path_cells != [ORIGIN, CHECKPOINT, DESTINATION]:
		check(false, "Audit route has the exact origin, checkpoint and destination, got %s" % [preview.path_cells])
		await _finish(level)
		return
	check(grid.can_unit_occupy_cell(vip, CHECKPOINT) == (scenario != Case.FALLBACK), "Passenger stopping legality is independent of traversal")
	if scenario == Case.FALLBACK:
		check(grid.get_unit_at(ESCORT) == escort and not grid.can_unit_occupy_cell(vip, ESCORT), "The occupied fallback is unavailable")
		check(grid.get_cell_data(ORIGIN).can_stop and grid.can_unit_occupy_cell(vip, DESTINATION), "The route endpoints are equally distant standable fallbacks")
	if not capture_dir.is_empty():
		level.action_camera_director.frequency = ActionCameraDirector.Frequency.COMBAT_ONLY
		var camera := level.get_node("CameraRig") as TacticalCamera
		camera.focus_position(grid.grid_to_world(CHECKPOINT))
		camera._manual_pitch = true
		camera.rotation = Vector3(deg_to_rad(-30.0), deg_to_rad(-145.0), 0)
		camera._set_zoom(9.0)
		await create_timer(0.45).timeout
		await _capture("01-carrying")
	var expected := ORIGIN if scenario in [Case.FALLBACK, Case.ARCHIVE] else CHECKPOINT
	var commits := [0]
	service.action_committed.connect(func(result):
		if not result is MoveActionResult: return
		commits[0] += 1
		if scenario in [Case.CHECKPOINT, Case.FALLBACK]:
			check(grid.get_unit_at(expected) == vip and not vip.visible and not carrier.is_carrying_unit(), "Commit settles occupancy and ownership before revealing the passenger"))
	var before := service.state_revision
	var receipt := await _move_and_capture(service, carrier, vip)
	if not receipt:
		check(false, "Production Move returns a receipt")
		await _finish(level)
		return
	check(commits[0] == 1 and receipt.base_revision == before and receipt.committed_revision == before + 1
		and service.state_revision == before + 1 and receipt.actor_ap_after == receipt.actor_ap_before - 1, "Move spends one AP and commits one revision")
	check(receipt.presentation_completed and receipt.presentation_error.is_empty() and not service.is_busy, "Move presentation finishes and releases the action barrier")
	if scenario == Case.SURVIVES:
		check(not receipt.movement_interrupted and receipt.target_cell == DESTINATION and grid.get_unit_at(DESTINATION) == carrier, "Nonlethal Guard allows the complete move")
		check(not receipt.reaction_events.is_empty() and receipt.reaction_events[0].damage > 0 and carrier.carried_unit == vip and not vip.visible, "A nonlethal hit leaves the passenger attached")
	else:
		check(receipt.movement_interrupted and receipt.path_cells == [ORIGIN, CHECKPOINT] and receipt.target_cell == CHECKPOINT, "Lethal Guard truncates the committed route")
		check(receipt.request.destination == DESTINATION and receipt.carried_actor_id.is_empty(), "Receipt retains requested destination and clears ownership")
		check(receipt.reaction_events.size() == 1 and receipt.reaction_events[0].checkpoint_cell == CHECKPOINT
			and receipt.reaction_events[0].target_defeated and second_watcher.tactical_state.is_overwatching, "A lethal reaction stops later watchers")
		check(grid.get_unit_at(ORIGIN) != carrier and grid.get_unit_at(DESTINATION) == null, "Neither endpoint contains the defeated carrier")
		check(level.find_children("RescuePassenger", "", true, false).is_empty(), "The visual attachment is gone")
		if scenario == Case.LOST:
			check(not vip.visible and not grid.occupancy_map.values().has(vip) and receipt.passenger_release.get("cell") == [], "The lost passenger remains hidden and off-grid")
			check(level.objective_manager.get_objective(&"extract_rescue").is_failed(), "No available stop fails the existing VIP extraction objective")
		else:
			check(grid.get_unit_at(expected) == vip and vip.grid_position == expected, "VIP released at %s (actual %s)" % [expected, vip.grid_position])
			check(vip.visible and vip.get_mission_id() == mission_id and vip.awaiting_rescue, "The released VIP preserves mission identity and incapacitation")
			check(vip.global_position.is_equal_approx(grid.grid_to_world(expected) + Vector3.UP * vip.standing_height), "Visual transform agrees with occupancy")
			check(level.objective_manager.get_objective(&"rescue").is_active(), "Rescue reopens after release")
			if scenario == Case.CHECKPOINT:
				check(grid.get_unit_at(ORIGIN) == null, "The legal checkpoint has priority over the origin")
				if not capture_dir.is_empty():
					await create_timer(0.35).timeout
					await _capture("04-settled")
				await process_frame
				level.turn_manager.select_player_unit(escort)
				check(await level.objective_manager.try_rescue(escort, vip) and escort.carried_unit == vip, "A second MIRA rescues the released VIP")
				if not capture_dir.is_empty(): await _capture("05-recovered")
	var wire := record.to_dictionary()
	if scenario == Case.ARCHIVE:
		wire.battle_configuration.erase("checkpoint_passenger_release")
	var restored := BattleReplayRecording.from_dictionary(JSON.parse_string(JSON.stringify(wire)))
	check(restored.is_playable(), "The production recording round-trips (%s)" % restored.validation_message())
	await _finish(level)
	if capture_dir.is_empty() and restored.is_playable() and scenario != Case.SURVIVES:
		await _play_case(restored, scenario)
		if scenario == Case.CHECKPOINT: await _play_case(restored, scenario)

func _play_case(record: BattleReplayRecording, scenario: Case) -> void:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_replay(record)
	level.battle_initialization_finished.connect(func(success: bool, _errors: Array):
		if success: _prepare(level, scenario), CONNECT_ONE_SHOT)
	root.add_child(level)
	var deadline := Time.get_ticks_msec() + 15000
	while not level.battle_initialization_attempted and Time.get_ticks_msec() < deadline:
		await process_frame
	var player := level.get_node_or_null("BattleReplayPlayer") as BattleReplayPlayer
	check(is_instance_valid(player), "Replay reconstructs the authored mission")
	if player:
		player.set_playback_speed(4.0)
		while not player.playback_complete and Time.get_ticks_msec() < deadline:
			await process_frame
		check(player.playback_succeeded and player.verified_actions == record.actions.size(), "Replay verifies receipts and fingerprints for %s (%s)" % [Case.keys()[scenario], player.last_divergence])
	await _finish(level)

func _move_and_capture(service: TacticalActionService, carrier: TacticalUnit, vip: TacticalUnit) -> MoveActionResult:
	var request := service.make_move_request(carrier, DESTINATION, TacticalActionRequest.Source.PLAYER)
	if capture_dir.is_empty():
		return await service.submit_move(request)
	var result: Array[MoveActionResult] = []
	var submit := func() -> void: result.append(await service.submit_move(request))
	submit.call()
	var deadline := Time.get_ticks_msec() + 10000
	while not carrier.is_moving and result.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	await _capture("02-moving")
	while not vip.visible and result.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	await _capture("03-impact")
	while result.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	return result[0] if not result.is_empty() else null

func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(capture_dir.path_join(filename + ".png")) == OK, "Rendered frame saved: " + filename)
