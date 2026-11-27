extends SceneTree
## The audit shape on a real authored deck. The fixture places units on the deck
## before capture, then uses the ordinary player queries, actions and replay.

const BATTLE := preload("res://levels/prototype_map/prototype_map.tscn")
const PARCEL := preload("res://art/environments/authored/parcels/surface_fit_range.tscn")
const LocalParcelContent := preload("res://systems/generation2/local_parcel_content.gd")
const TARGET := Vector3i(8, 2, 19)
const START := Vector3i(8, 2, 18)
const WATCHER := Vector3i(7, 2, 17)
var failures := 0
var capture_dir := ""
var capture_legacy := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] in ["capture", "capture-legacy"] and DisplayServer.get_name() != "headless":
		capture_dir = args[1]
		capture_legacy = args[0] == "capture-legacy"
		DirAccess.make_dir_recursive_absolute(capture_dir)
	var packed := _parcel()
	var archived := LocalParcelContent.archive(packed)
	if not _check(archived.has("content"), "Capture the authored parcel and exact dependencies"):
		quit(1)
		return
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.PARCEL_TEST)
	config.player_count = 1
	config.enemy_count = 1
	config.battle_seed = 16
	config.engagement_policy = CombatRules.EngagementPolicy.HEAD_CORE_SYMMETRIC
	config.content_manifest = {"local_content": archived.content}
	if capture_legacy:
		var compiled := BattlefieldCatalog.generate(BattlefieldCatalog.PARCEL_TEST, Vector2i(32, 32), 16, 1.0, config.content_manifest)
		config.content_manifest = compiled.content_manifest.duplicate(true)
		config.content_manifest.compiler_revision = 10
		config.content_manifest.erase("standing_points_signature")
	var level := BATTLE.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	current_scene = level
	if not _check(level.battle_initialization_succeeded, "Initialize the ordinary parcel battle"):
		quit(1)
		return
	_place_fixture_units(level)
	var grid := level.battle_controller.grid_manager
	var battle := level.battle_controller
	var service := battle.action_service
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var watcher: TacticalUnit = level.turn_manager.enemy_units[0]
	var tile := grid.get_cell_data(TARGET)
	if capture_legacy:
		_check(not tile.can_stop and not battle.query_move(actor, TARGET).is_legal(), "Revision 10 rejects the same hovered deck tile")
		_frame_deck(level, tile.support_center + Vector3.FORWARD * 0.42)
		await _capture("00-legacy-walkability")
		quit(1 if failures else 0)
		return
	var legacy_manifest := grid.map_data.content_manifest.duplicate(true)
	legacy_manifest.compiler_revision = 10
	legacy_manifest.erase("standing_points_signature")
	var legacy := BattlefieldCatalog.generate(BattlefieldCatalog.PARCEL_TEST, Vector2i(32, 32), 16, 1.0, legacy_manifest)
	if not _check(tile != null and tile.can_stop and tile.world_position.is_equal_approx(tile.support_center + Vector3(0, 0, -0.42)), "New compiler recovers a canonical north offset"):
		quit(1)
		return
	_check(legacy.generation_errors.is_empty() and not legacy.get_cell(TARGET).can_stop, "Exact archived content with compiler 10 retains its rejected tile")
	_check(legacy.content_manifest.standing_points_signature != grid.map_data.content_manifest.standing_points_signature, "Changed canonical state is distinguishable from revision 10")
	_check(not SurfaceNavigation.supported(grid.map_data, tile.support_center + Vector3(0.33, 0, 0), grid.map_data.body_radius), "Clear east candidate still fails support above the visible edge")
	var inventory := battle.query_move(actor)
	var query := battle.query_move(actor, TARGET)
	if not _check(TARGET in inventory.legal_destination_cells and query.is_legal() and query.path_cells == [START, TARGET], "Shared movement inventory and target preview use the legal cardinal approach"):
		quit(1)
		return
	_check(is_equal_approx(query.path_cost, 1.0) and query.path[-1] == tile.world_position, "Logical route weight is one and preview ends at canonical XYZ")
	var planning := battle.pathfinder.calculate_path_with_occupancy(START, TARGET, grid, actor)
	_check(planning == query.path, "Hypothetical AI route agrees with targeted Move")
	_place(grid, actor, START + Vector3i.FORWARD)
	_place(grid, watcher, TARGET)
	_check(not battle.query_move(actor, TARGET).is_legal() and TARGET not in battle.query_move(actor).legal_destination_cells, "A live occupant invalidates the recovered destination")
	_place(grid, watcher, WATCHER)
	_place(grid, actor, START)
	var record: BattleReplayRecording = level._replay_recorder.recording
	record.initial_state_fingerprint = BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager)
	watcher.tactical_state.establish_overwatch()
	var guard_before := service.query_guard_reaction(watcher, actor, TARGET)
	watcher.tactical_state.clear_overwatch()
	var attack_preview := CombatRules.evaluate_attack_from_cell(actor, TARGET, watcher, grid, null)
	var ap := actor.stats.current_ap
	if not capture_dir.is_empty():
		_frame_deck(level, tile.world_position)
		await _capture("01-walkability")
		battle.toggle_move_mode()
		_check(TARGET in battle.current_movement_zone, "Ordinary Move mode draws the recovered tile in range")
		battle.call("_update_movement_preview", {"position": tile.world_position})
		_check(is_instance_valid(battle.movement_ghost) and battle.call("_toggle_destination_inspection"), "Production hover creates the destination hologram and can pin the tile")
		await _capture("02-preview")
		battle.toggle_move_mode()
	var receipt := await _submit_move(service, actor)
	if not _check(receipt != null, "Authoritative Move commits"):
		quit(1)
		return
	_check(receipt.path_cells == query.path_cells and receipt.committed_revision == receipt.base_revision + 1 and actor.stats.current_ap == ap - 1, "Previewed path commits once for one AP")
	_check(grid.get_unit_at(START) == null and grid.get_unit_at(TARGET) == actor, "Occupancy settles exclusively at destination")
	_check(actor.global_position.is_equal_approx(tile.world_position + Vector3.UP * actor.standing_height), "Actor arrives at canonical stand point")
	var attack := CombatRules.evaluate_attack(actor, watcher, grid, null)
	_check(attack.is_legal == attack_preview.is_legal and attack.aim_point == attack_preview.aim_point and attack.cover_type == attack_preview.cover_type, "Combined shot and cover preview agree after arrival")
	watcher.tactical_state.establish_overwatch()
	var guard_after := service.query_guard_reaction(watcher, actor, TARGET)
	_check(guard_before.can_fire and guard_after.can_fire and guard_before.evaluation.aim_point == guard_after.evaluation.aim_point, "Guard is legal and both checkpoints use the same aim point")
	watcher.tactical_state.clear_overwatch()
	if not capture_dir.is_empty():
		await create_timer(0.35).timeout
		await _capture("03-arrival")
	var wire := BattleReplayRecording.from_dictionary(JSON.parse_string(JSON.stringify(record.to_dictionary())))
	level.queue_free()
	await process_frame
	_check(wire.is_playable() and wire.actions.size() == 1, "The new recording contains one verifiable Move")
	var replay := BATTLE.instantiate() as BattleLevel
	replay.configure_replay(wire)
	replay.battle_initialization_finished.connect(func(success: bool, _issues: Array):
		if success: _place_fixture_units(replay), CONNECT_ONE_SHOT)
	root.add_child(replay)
	var player := replay.get_node_or_null("BattleReplayPlayer") as BattleReplayPlayer
	if _check(is_instance_valid(player), "Playback reconstructs the authored deck from the recorded compiler and content"):
		player.set_playback_speed(4.0)
		var deadline := Time.get_ticks_msec() + 10000
		while not player.playback_complete and Time.get_ticks_msec() < deadline:
			await process_frame
		_check(player.playback_succeeded and player.verified_actions == 1, "Playback verifies corrected XYZ, receipt and state fingerprint: " + player.last_divergence)
	print("Support-aware surface battle: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _place_fixture_units(level: BattleLevel) -> void:
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	var grid := level.battle_controller.grid_manager
	_place(grid, level.turn_manager.player_units[0], START)
	_place(grid, level.turn_manager.enemy_units[0], WATCHER)

func _frame_deck(level: BattleLevel, point: Vector3) -> void:
	var camera := level.get_node("CameraRig") as TacticalCamera
	camera.focus_position(point)
	camera._manual_pitch = true
	camera.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(39.0), 0)
	camera._set_zoom(8.5)
	var debug := level.get_node("Visualizers/BattleUI/DebugTools") as DebugTools
	debug.call("_set_walkability_visible", true)

func _submit_move(service: TacticalActionService, actor: TacticalUnit) -> MoveActionResult:
	var request := service.make_move_request(actor, TARGET, TacticalActionRequest.Source.PLAYER)
	if capture_dir.is_empty(): return await service.submit_move(request)
	var results: Array[MoveActionResult] = []
	var submit := func(): results.append(await service.submit_move(request))
	submit.call()
	await create_timer(0.075).timeout
	_check(actor.is_moving, "Actor traverses the route in ordinary gameplay presentation")
	await _capture("02b-approach")
	while results.is_empty(): await process_frame
	return results[0]

func _place(grid: GridManager, actor: TacticalUnit, cell: Vector3i) -> void:
	_check(grid.can_unit_occupy_cell(actor, cell), "Fixture placement is legal at %s" % cell)
	grid.update_unit_position(actor, actor.grid_position, cell)
	actor.global_position = grid.grid_to_world(cell) + Vector3.UP * actor.standing_height

func _parcel() -> PackedScene:
	var parcel := PARCEL.instantiate() as Node3D
	_box(parcel, Vector3(7, 1.89, 19), Vector3(3, 0.22, 5), Color("587a7c"))
	var deck := Node3D.new()
	deck.name = "AuthoredDeck"
	parcel.add_child(deck)
	deck.owner = parcel
	deck.set_meta("deck_local_rect", Rect2i(6, 17, 3, 5))
	deck.set_meta("deck_level", 2)
	var obstacle := _box(parcel, Vector3(7.78, 2.9, 19), Vector3(0.46, 1.8, 0.2), Color("d28c45"))
	obstacle.set_meta("solid_size", Vector3(0.46, 1.8, 0.2))
	var packed := PackedScene.new()
	_check(packed.pack(parcel) == OK, "Pack the fixture using the same local parcel workflow")
	parcel.free()
	return packed

func _box(parcel: Node3D, point: Vector3, size: Vector3, tint: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	node.mesh = box
	node.position = point
	parcel.add_child(node)
	node.owner = parcel
	return node

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(capture_dir.path_join(name + ".png")) == OK, "Capture " + name)

func _check(ok: bool, message: String) -> bool:
	if not ok:
		failures += 1
		push_error(message)
	return ok
