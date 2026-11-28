extends SceneTree
## Production Rescue and Move in the authored Range with independent visual rigs.
const Fixture := preload("res://tests/support/ai_scenario_fixture.gd")
const BOTTOM := Vector3i(12, 0, 4)
const TOP := Vector3i(12, 3, 5)
const APPROACH := Vector3i(11, 0, 4)
const UPPER_EXIT := Vector3i(12, 3, 6)
const MODELS := [&"mira_0", &"small_mira_0"]
var checks := 0
var failures := 0
var capture_dir := ""

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	create_timer(170.0, true, false, true).timeout.connect(func(): quit(2))
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "capture" and DisplayServer.get_name() != "headless":
		capture_dir = args[1]
		DirAccess.make_dir_recursive_absolute(capture_dir)
	var reference := {}
	for carrier in MODELS:
		for passenger in MODELS:
			var pair := await _pair(carrier, passenger)
			if carrier == MODELS[0] and passenger == MODELS[1]:
				reference = pair
	if not reference.is_empty():
		var skipped := await _pair(MODELS[0], MODELS[1], true)
		_check(not skipped.is_empty() and skipped == reference, "Suppressed presentation keeps the same Move receipts, RNG and fingerprints")
	if capture_dir.is_empty():
		await _check_ladder_reaction(false)
		await _check_ladder_reaction(true)
		await _check_ai_extraction()
		await _check_teardown()
		await _check_unknown_passenger()
	print("Tactical mixed carry and ladder: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _pair(carrier_model: StringName, passenger_model: StringName, suppressed := false) -> Dictionary:
	var f := Fixture.new()
	var mission := MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.RESCUE, 1, false)
	await f.setup(self, 1, 1, 0, mission, AIDifficultyPolicy.Tier.HARD, [], true)
	var carrier := f.turns.player_units[0]
	var vip := f.level.get_node_or_null("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	_check(is_instance_valid(vip), "Production Range has a Rescue target")
	if not is_instance_valid(vip):
		await f.dispose(self)
		return {}
	_replace_visual(carrier, carrier_model, f.grid)
	_replace_visual(vip, passenger_model, f.grid)
	f.place(carrier, APPROACH)
	f.place(vip, APPROACH + Vector3i.BACK)
	f.ready_actor(carrier, 3, 4)
	f.act_as(carrier)
	var label := "%s-%s" % [carrier_model, passenger_model]
	var adapter := carrier.visual_adapter
	var service := f.battle.action_service
	if not capture_dir.is_empty() and not suppressed:
		var camera := f.level.get_node("CameraRig") as TacticalCamera
		camera.focus_position((f.grid.grid_to_world(BOTTOM) + f.grid.grid_to_world(TOP)) * 0.5)
		camera._manual_pitch = true
		camera.rotation = Vector3(deg_to_rad(-18.0), deg_to_rad(-140.0), 0)
		camera._set_zoom(9.0)
		await create_timer(0.4).timeout
	var expected := vip.get_passenger_definition()
	var vip_id := vip.get_mission_id()
	var recording: BattleReplayRecording = f.level._replay_recorder.recording
	recording.initial_state_fingerprint = BattleStateFingerprint.capture(f.turns, f.grid, f.level.objective_manager)
	_check(expected.character_id == passenger_model, label + " resolves the actual casualty before Rescue")
	var rescued := await f.level.objective_manager.try_rescue(carrier, vip)
	_check(rescued and carrier.carried_unit == vip and not vip.visible and not f.grid.occupancy_map.values().has(vip),
		label + " Rescue keeps one authoritative VIP off the grid")
	var carried: Node3D = adapter.rig.carry_passenger
	_check(is_instance_valid(carried), label + " builds a passive carried body")
	if not is_instance_valid(carried):
		await f.dispose(self)
		return {}
	_check(carried.definition.is_same_body_as(vip.visual_adapter.rig) and carried.definition.character_id == passenger_model
		and adapter.rig.is_weapon_stowed(), label + " preserves the passenger model, profile, scale and stow")
	await _capture(label + "-pickup", suppressed)
	var ghost := MovementGhost.new()
	f.level.add_child(ghost)
	ghost.show_destination(carrier, BOTTOM, f.grid)
	_check(is_instance_valid(ghost.model.rig.carry_passenger)
		and ghost.model.rig.carry_passenger.definition.is_same_body_as(vip.visual_adapter.rig), label + " preview shows the same passenger")
	ghost.free()
	var records := {}
	for destination in [UPPER_EXIT, APPROACH]:
		var query := f.battle.query_move(carrier, destination)
		var previous := carrier.grid_position
		_check(query.is_legal() and BOTTOM in query.path_cells and TOP in query.path_cells,
			label + " queries a route with approach, ladder, and onward segment")
		var moved := await _watch_move(service, carrier, destination, carried, label, suppressed)
		_check(moved != null and moved.presentation_completed and moved.presentation_error.is_empty()
			and moved.path_cells == query.path_cells and carrier.grid_position == destination
			and f.grid.get_unit_at(previous) == null and f.grid.get_unit_at(destination) == carrier,
			label + " settles exactly on the committed route and occupancy")
		if moved:
			records[str(destination)] = [moved.to_replay_record(), service.get_combat_rng_state(),
				BattleStateFingerprint.capture(f.turns, f.grid, f.level.objective_manager)]
		_check(carrier.carried_unit == vip and vip.get_mission_id() == vip_id and adapter.rig.carry_passenger == carried
			and adapter.rig.is_weapon_stowed() and not adapter.rig.loaded_ladder_active(),
			label + " restores ordinary carry before completing Move")
		await _capture(label + ("-upper" if destination == UPPER_EXIT else "-lower"), suppressed)
	var playback: BattleReplayRecording
	if suppressed:
		playback = BattleReplayRecording.from_dictionary(JSON.parse_string(JSON.stringify(recording.to_dictionary())))
	var released := f.level.objective_manager.release_carried_unit(carrier, carrier.grid_position)
	_check(released and not carrier.is_carrying_unit() and vip.visible and vip.get_mission_id() == vip_id
		and f.grid.get_unit_at(vip.grid_position) == vip and not is_instance_valid(carried)
		and not adapter.rig.is_weapon_stowed(), label + " releases the original VIP and removes the passive body")
	await _capture(label + "-release", suppressed)
	await f.dispose(self)
	if playback != null:
		await _check_playback(playback, carrier_model, passenger_model)
	return records

func _replace_visual(actor: TacticalUnit, model: StringName, grid: GridManager) -> void:
	var was_incapacitated := actor.awaiting_rescue
	var old := actor.visual_adapter
	var scene := load("res://art/characters/%s/runtime/%s_unit_visual.tscn" % [model, model]) as PackedScene
	var adapter := scene.instantiate() as TacticalCharacterAdapter
	actor.visual_adapter = adapter
	old.free()
	adapter.presentation_grid = grid
	adapter.position = Vector3.DOWN * actor.standing_height
	actor.add_child(adapter)
	adapter.setup(actor)
	if was_incapacitated:
		adapter.present_incapacitated(true)

func _check_playback(recording: BattleReplayRecording, carrier_model: StringName, passenger_model: StringName) -> void:
	_check(recording.is_playable() and recording.actions.size() == 3, "Rescue and both loaded Moves round-trip through JSON")
	if not recording.is_playable():
		return
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_replay(recording)
	level.battle_initialization_finished.connect(func(ok: bool, _errors: Array):
		if not ok:
			return
		var f := Fixture.new()
		f.grid = level.battle_controller.grid_manager
		f.turns = level.turn_manager
		var carrier := f.turns.player_units[0]
		var vip := level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
		_replace_visual(carrier, carrier_model, f.grid)
		_replace_visual(vip, passenger_model, f.grid)
		f.place(carrier, APPROACH)
		f.place(vip, APPROACH + Vector3i.BACK)
		f.ready_actor(carrier, 3, 4)
		f.act_as(carrier)
	, CONNECT_ONE_SHOT)
	root.add_child(level)
	await process_frame
	var player := level.get_node_or_null("BattleReplayPlayer") as BattleReplayPlayer
	if player != null:
		player.set_playback_speed(4.0)
		var deadline := Time.get_ticks_msec() + 20000
		while not player.playback_complete and Time.get_ticks_msec() < deadline:
			await process_frame
		var carrier := level.turn_manager.player_units[0]
		var carried := carrier.visual_adapter.rig.carry_passenger
		_check(player.playback_succeeded and player.verified_actions == 3 and carrier.grid_position == APPROACH
			and is_instance_valid(carried) and carried.definition.character_id == passenger_model,
			"Playback verifies Rescue, loaded movement and the resolved visual body: " + player.last_divergence)
	else:
		_check(false, "Mixed carry playback initializes")
	level.queue_free()
	await process_frame

func _watch_move(service: TacticalActionService, carrier: TacticalUnit, destination: Vector3i, carried: Node3D,
		label: String, suppressed: bool) -> MoveActionResult:
	var done: Array[MoveActionResult] = []
	var request := service.make_move_request(carrier, destination, TacticalActionRequest.Source.PLAYER)
	var submit := func(): done.append(await service.submit_move(request, suppressed))
	var start := Time.get_ticks_msec()
	var transfer_start := -1
	var transfer_seconds := 0.0
	var full_climb := false
	var restored_while_busy := false
	var attached := true
	var captured_transfer := false
	var captured_restore := false
	var captured_rungs := false
	var height_in_transfer := NAN
	var stable_transfer := true
	var rig := carrier.visual_adapter.rig
	var direction := "up" if destination.y > 0 else "down"
	submit.call()
	while done.is_empty() and Time.get_ticks_msec() - start < 20000:
		await process_frame
		attached = attached and rig.carry_passenger == carried and rig.is_weapon_stowed()
		if rig.ladder != null and not rig.loaded_ladder_ready():
			if transfer_start < 0:
				transfer_start = Time.get_ticks_msec()
				height_in_transfer = carrier.global_position.y
			stable_transfer = stable_transfer and is_equal_approx(carrier.global_position.y, height_in_transfer)
			if not captured_transfer and rig.loaded_ladder.blend >= 0.5:
				captured_transfer = true
				await _capture(label + "-" + direction + "-transfer", suppressed)
		if rig.ladder != null and rig.loaded_ladder != null and rig.loaded_ladder.blend > 0.999:
			if not full_climb:
				transfer_seconds = (Time.get_ticks_msec() - transfer_start) / 1000.0
			full_climb = true
			if not captured_rungs and absf(rig.ladder.climbed - rig.ladder.length * 0.5) < 0.04:
				captured_rungs = true
				await _capture(label + "-" + direction + "-rungs", suppressed)
		if rig.ladder == null and rig.loaded_ladder_active():
			restored_while_busy = restored_while_busy or (carrier.is_moving and service.is_busy)
			if not captured_restore and rig.loaded_ladder.blend <= 0.5:
				captured_restore = true
				await _capture(label + "-" + direction + "-restore", suppressed)
	if not suppressed:
		_check(transfer_start >= 0 and stable_transfer and full_climb, label + " " + direction + " holds height until transfer completes")
		_check(restored_while_busy and attached, label + " " + direction + " waits for attached carry restoration")
		print("[Loaded ladder] ", label, " ", direction, " total_ms=", Time.get_ticks_msec() - start, " transfer_s=", transfer_seconds)
	return done[0] if not done.is_empty() else null

func _ready_rescue(legacy_passenger := false) -> Fixture:
	var mission := MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.RESCUE, 1, false)
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, mission, AIDifficultyPolicy.Tier.HARD, [], true)
	var carrier := f.turns.player_units[0]
	var vip := f.level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	f.place(carrier, APPROACH)
	f.place(vip, APPROACH + Vector3i.BACK)
	vip.use_legacy_bean = legacy_passenger
	f.act_as(carrier)
	_check(await f.level.objective_manager.try_rescue(carrier, vip), "Rescue collects the VIP in the tactical fixture")
	return f

func _check_ladder_reaction(lethal: bool) -> void:
	var f := await _ready_rescue()
	var carrier := f.turns.player_units[0]
	var watcher := f.turns.enemy_units[0]
	var vip := carrier.carried_unit
	var adapter := carrier.visual_adapter
	var service := f.battle.action_service
	# Start at the foot so the landing is the first logical reaction checkpoint.
	f.place(carrier, BOTTOM)
	f.place(watcher, Vector3i(12, 3, 7))
	watcher.attack_range = 10
	_check(watcher.tactical_state.establish_overwatch(), "Watcher prepares one reaction")
	if lethal:
		carrier.stats.current_hp = 1
	var opportunity := service.query_guard_reaction(watcher, carrier, TOP)
	_check(opportunity.get("can_fire", false), "Guard is legal at the occupied-floor landing")
	if opportunity.get("can_fire", false):
		var rng := RandomNumberGenerator.new()
		for seed_value in range(1000):
			rng.seed = seed_value
			if AttackActionResult.roll_hits(rng.randf() * 100.0, opportunity.evaluation.hit_chance):
				service._combat_rng.seed = seed_value
				break
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.state = service.get_combat_rng_state()
	expected_rng.randf()
	var done: Array[MoveActionResult] = []
	var request := service.make_move_request(carrier, UPPER_EXIT, TacticalActionRequest.Source.PLAYER)
	var submit := func(): done.append(await service.submit_move(request))
	var saw_back_carry := false
	var start := Time.get_ticks_msec()
	submit.call()
	while done.is_empty() and Time.get_ticks_msec() - start < 20000:
		await process_frame
		if is_instance_valid(adapter) and adapter.rig.loaded_ladder_active() and is_instance_valid(adapter.rig.carry_passenger):
			saw_back_carry = true
	var result := done[0] if not done.is_empty() else null
	_check(result != null and result.presentation_completed and result.presentation_error.is_empty()
		and result.reaction_events.size() == 1 and saw_back_carry and not service.is_busy,
		"Reactive Move shows the back carry and settles one reaction and the action barrier")
	if result and result.reaction_events.size() == 1:
		var event := result.reaction_events[0]
		_check(event.checkpoint_index == 1 and event.checkpoint_cell == TOP and event.did_hit
			and event.target_defeated == lethal and service.get_combat_rng_state() == expected_rng.state,
			"Guard consumes one draw at the authorized ladder landing")
		if lethal:
			_check(result.movement_interrupted and result.target_cell == TOP and vip.visible
				and f.grid.get_unit_at(TOP) == vip and vip.awaiting_rescue
				and (not is_instance_valid(adapter) or not is_instance_valid(adapter.rig.carry_passenger)),
				"Lethal landing releases the original VIP exactly at the committed checkpoint")
		else:
			_check(not result.movement_interrupted and f.grid.get_unit_at(UPPER_EXIT) == carrier
				and carrier.carried_unit == vip and not adapter.rig.loaded_ladder_active(),
				"Nonlethal landing restores carry and continues to the requested cell")
	await f.dispose(self)

func _check_ai_extraction() -> void:
	var f := await _ready_rescue()
	var carrier := f.turns.player_units[0]
	var vip := carrier.carried_unit
	var service := f.battle.action_service
	f.place(carrier, BOTTOM)
	var occupied := f.turns.enemy_units[0]
	f.place(occupied, TOP)
	var revision := service.state_revision
	var request := service.make_move_request(carrier, TOP, TacticalActionRequest.Source.PLAYER)
	_check(await service.submit_move(request) == null and service.last_rejection.code == &"occupied"
		and service.state_revision == revision, "Loaded Move rejects an occupied ladder landing")
	f.place(occupied, Vector3i(29, 0, 12))
	f.battle.debug_player_ai = true
	var ai := f.ai_of(carrier)
	ai._ensure_policy()
	ai._squad_context = f.battle.get_squad_context(carrier)
	ai.current_mission_intent = ai._get_ai_mission_intent()
	var receipts: Array = []
	service.action_committed.connect(func(result): receipts.append(result))
	var climbed := await ai._move_toward_cell(TOP, false, "tactical extraction route")
	_check(climbed and receipts.size() == 1 and receipts[0].request.source == TacticalActionRequest.Source.AI
		and receipts[0].path_cells == [BOTTOM, TOP] and receipts[0].presentation_completed
		and not service.is_busy and not carrier.visual_adapter.rig.loaded_ladder_active(),
		"AI waits for one committed ladder presentation and releases the action barrier")
	var stops := f.grid.map_data.get_objective_zone(&"extract")
	for stop: Vector3i in stops:
		if f.grid.can_unit_occupy_cell(carrier, stop):
			f.place(carrier, stop)
			break
	_check(await f.level.objective_manager.try_extract(carrier) and f.level.objective_manager.extracted_vips == 1,
		"Production extraction records the same carried VIP once")
	await process_frame
	_check(not is_instance_valid(vip) and not is_instance_valid(carrier), "Extraction cleans up both authoritative actors")
	await f.dispose(self)

func _check_teardown() -> void:
	var f := await _ready_rescue()
	var carrier := f.turns.player_units[0]
	var adapter := carrier.visual_adapter
	var passive := adapter.rig.carry_passenger
	f.place(carrier, BOTTOM)
	var service := f.battle.action_service
	var request := service.make_move_request(carrier, TOP, TacticalActionRequest.Source.PLAYER)
	service.submit_move(request)
	var deadline := Time.get_ticks_msec() + 5000
	while not adapter.rig.loaded_ladder_active() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(service.is_busy and adapter.rig.loaded_ladder_active() and not adapter.rig.loaded_ladder_ready(),
		"Teardown starts during the real transfer with the Move barrier held")
	await f.dispose(self)
	_check(not is_instance_valid(adapter) and not is_instance_valid(passive) and not is_instance_valid(service),
		"Removing the tactical battle frees the in-flight carry and pending movement presentation")

func _check_unknown_passenger() -> void:
	var f := await _ready_rescue(true)
	var carrier := f.turns.player_units[0]
	var rig := carrier.visual_adapter.rig
	_check(carrier.is_carrying_unit() and not is_instance_valid(rig.carry_passenger) and rig.is_weapon_stowed(),
		"A non-humanoid casualty keeps tactical ownership without inventing a carried model")
	f.place(carrier, BOTTOM)
	_check(await f.battle.try_move(carrier, TOP) and f.grid.get_unit_at(TOP) == carrier,
		"An unavailable visual body still uses the legal ladder Move")
	await f.dispose(self)

func _capture(label: String, suppressed: bool) -> void:
	if capture_dir.is_empty() or suppressed:
		return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(capture_dir.path_join(label + ".png")) == OK, "Captured " + label)
