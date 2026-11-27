extends SceneTree

const Battle := preload("res://levels/prototype_map/prototype_map.tscn")
const START := Vector3i(25, 0, 6)
const VALID := Vector3i(26, 0, 6)
const TANK := Vector3i(30, 0, 8)
const RangeFixture := preload("res://tests/support/ai_scenario_fixture.gd")
var failures := 0
var capture_dir := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "capture" and DisplayServer.get_name() != "headless":
		capture_dir = args[1]
		DirAccess.make_dir_recursive_absolute(capture_dir)
	await _depot()
	await _layered_range()
	print("Movement readability: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _depot() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.SERVICE_DEPOT)
	config.battle_seed = 16
	var level := Battle.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	var battle := level.battle_controller
	var grid := battle.grid_manager
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	_place(grid, actor, START)
	battle.toggle_move_mode()
	battle._update_movement_preview({"position": grid.grid_to_world(VALID)})
	_check(battle.query_move(actor, VALID).is_legal() and not battle._last_tactical_preview.is_empty(), "Known valid Depot stop shows its preview")
	var service := battle.action_service
	var snapshot := BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager)
	var rng := service.get_combat_rng_state()
	var revision := service.state_revision
	var tx := service.last_transaction_id
	var point := grid.get_cell_data(TANK).support_center
	battle._update_movement_preview({"position": point})
	_check(battle.query_move(actor, TANK).validation.code == &"cannot_stand", "The tank center has a specific authoritative standing rejection")
	_check(battle._last_tactical_preview == "Cannot stand here.", "Hover describes the blocked tank center")
	await battle._on_floor_clicked(point)
	_check(battle._last_tactical_preview == "Cannot stand here.", "Click describes the same rejection")
	_check(service.get_combat_rng_state() == rng and service.state_revision == revision and service.last_transaction_id == tx
		and BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager) == snapshot,
		"Rejected hover and click preserve AP, occupancy, revision, receipts and RNG")
	if not capture_dir.is_empty(): await _capture_depot(level)
	var tank := grid.get_cell_data(TANK)
	var old_support := tank.support_surface
	tank.support_surface = false
	_expect(battle, TANK, &"unsupported", "Cannot stand here.")
	tank.support_surface = old_support
	tank.walkable = true
	_expect(battle, TANK, &"transit_only", "Cannot stop here.")
	tank.walkable = false
	_expect(battle, Vector3i(999, 0, 999), &"invalid_destination", "No destination here.")
	_expect(battle, START, &"already_there", "Already here.")
	var speed := actor.stats.speed
	actor.stats.speed = 0
	_expect(battle, VALID, &"beyond_movement_range", "Beyond movement range.")
	actor.stats.speed = speed
	var start_id: int = battle.pathfinder.grid_to_id_map[START]
	var steps := battle.pathfinder.astar.get_point_connections(start_id)
	for step in steps: battle.pathfinder.astar.disconnect_points(start_id, step)
	_expect(battle, VALID, &"path_unavailable", "No available route.")
	for step in steps: battle.pathfinder.astar.connect_points(start_id, step)
	var available := actor.stats.current_ap
	actor.stats.set_available_ap_for_setup(0)
	_expect(battle, VALID, &"insufficient_ap", "Not enough AP")
	actor.stats.set_available_ap_for_setup(available)
	_check(service.query_move(&"missing", VALID).validation.code == &"actor_missing", "Invalid actor is rejected by the action service")
	var enemy: TacticalUnit = level.turn_manager.enemy_units[0]
	var enemy_home := enemy.grid_position
	var hit := {"grid_position": VALID}
	battle._update_movement_preview(hit)
	_check(battle._preview_query != null and battle._toggle_destination_inspection(), "V pins the valid movement preview")
	_check(battle._last_tactical_preview.contains("Destination pinned"), "Pin retains existing contextual inspection")
	var preview_model := battle.movement_ghost.model
	_place(grid, enemy, VALID)
	battle._update_movement_preview(hit)
	_check(battle.query_move(actor, VALID).validation.code == &"occupied"
		and battle._last_tactical_preview == "Destination occupied by %s." % enemy.get_display_name()
		and battle._pinned_destination == BattleController.NO_PREVIEW_CELL and not battle.movement_ghost.visible,
		"A changed occupant invalidates the cached pin and clears the ghost")
	_check(battle.movement_ghost.model == preview_model and not preview_model.can_process(), "An invalid hover suspends its hidden rig")
	enemy.hide()
	battle._update_movement_preview(hit)
	_check(battle._last_tactical_preview == "Cannot stand here.", "A hidden actor is indistinguishable from unavailable standing space")
	enemy.show()
	_place(grid, enemy, enemy_home)
	battle._update_movement_preview(hit)
	_check(battle._preview_query != null and battle.movement_ghost.visible and battle.movement_ghost.model == preview_model
		and preview_model.can_process(), "Vacating the tile restores the same preview rig")
	battle._update_movement_preview({})
	_check(battle._last_tactical_preview.is_empty() and not battle.movement_ghost.visible, "Leaving the floor clears the preview")
	battle._update_movement_preview(hit)
	battle.toggle_move_mode()
	_check(battle._last_tactical_preview.is_empty() and not battle.movement_ghost.visible, "Cancel Move clears text and ghost immediately")
	battle.toggle_move_mode()
	battle._update_movement_preview(hit)
	level.turn_manager.select_player_unit(level.turn_manager.player_units[1])
	_check(not battle.is_move_mode_active and battle._last_tactical_preview.is_empty(), "Changing selection clears movement feedback")
	level.turn_manager.select_player_unit(actor)
	battle.toggle_move_mode()
	await _confirm_changed_occupancy(battle, actor, enemy, enemy_home)
	var previews: Array = []
	service.action_committed.connect(func(receipt): previews.append(receipt), CONNECT_ONE_SHOT)
	var query := battle.query_move(actor, VALID)
	var before_ap := actor.stats.current_ap
	BattleUXSettings.confirm_movement = false
	await battle._on_floor_clicked(grid.grid_to_world(VALID))
	_check(previews.size() == 1 and previews[0] is MoveActionResult and previews[0].path_cells == query.path_cells
		and service.last_transaction_id == tx + 1 and actor.stats.current_ap == before_ap - 1
		and grid.get_unit_at(VALID) == actor, "The next valid click commits its previewed route and one AP exactly once")
	_check(battle._last_tactical_preview.is_empty() and not battle.movement_ghost.visible, "Committed movement clears feedback")
	level.queue_free()
	await process_frame

func _expect(battle: BattleController, cell: Vector3i, code: StringName, text: String) -> void:
	battle.action_service.advance_external_revision()
	var query := battle.query_move(battle.tactical_unit, cell)
	battle._update_movement_preview({"grid_position": cell})
	_check(query.validation.code == code and battle._last_tactical_preview == text,
		"%s explains %s as %s (%s / %s)" % [cell, code, text, query.validation.code, battle._last_tactical_preview])

func _confirm_changed_occupancy(battle: BattleController, actor: TacticalUnit, enemy: TacticalUnit, enemy_home: Vector3i) -> void:
	var service := battle.action_service
	var grid := battle.grid_manager
	BattleUXSettings.load_preferences()
	BattleUXSettings.confirm_movement = true
	await battle._on_floor_clicked(grid.grid_to_world(VALID))
	_check(battle.action_confirmation != null and battle.action_confirmation.visible, "A valid click opens the existing Move confirmation")
	_place(grid, enemy, VALID)
	var before := BattleStateFingerprint.capture(battle.turn_manager, grid, null)
	var rng := service.get_combat_rng_state()
	var revision := service.state_revision
	await battle.action_confirmation._finish(true)
	_check(battle._last_tactical_preview.begins_with("Destination occupied") and not battle.movement_ghost.visible,
		"A newly occupied destination is explained on confirmation")
	_check(BattleStateFingerprint.capture(battle.turn_manager, grid, null) == before
		and service.get_combat_rng_state() == rng and service.state_revision == revision,
		"Rejecting confirmation preserves state and RNG")
	_place(grid, enemy, enemy_home)
	_check(actor.grid_position == START, "The invalid confirmation did not move the actor")

func _place(grid: GridManager, unit: TacticalUnit, cell: Vector3i) -> void:
	grid.update_unit_position(unit, unit.grid_position, cell)
	unit.global_position = grid.grid_to_world(cell) + Vector3.UP * unit.standing_height

func _capture_depot(level: BattleLevel) -> void:
	var battle := level.battle_controller
	var grid := battle.grid_manager
	var camera := level.get_node("CameraRig") as TacticalCamera
	camera.focus_position(grid.get_cell_data(TANK).support_center.lerp(grid.grid_to_world(VALID), 0.45))
	camera._manual_pitch = true
	camera.rotation = Vector3(deg_to_rad(-61.0), deg_to_rad(24.0), 0)
	camera._set_zoom(22.0)
	await physics_frame
	var point := grid.get_cell_data(TANK).support_center
	var pixel := camera.camera.unproject_position(point)
	var hit := battle.mouse_raycaster.get_floor_raycast_result(pixel)
	if hit.is_empty(): hit = battle.mouse_raycaster.rejected_floor_hit
	_check(hit.get("grid_position") == TANK, "Physical ray identifies the blocked tank tile for feedback")
	if hit.get("grid_position") == TANK:
		_push_click(pixel)
		_check(battle._last_tactical_preview == "Cannot stand here.", "Viewport click gives the real tank feedback")
		await _capture("01-depot-tank", func(): battle._update_movement_preview(hit))
	var valid_pixel := camera.camera.unproject_position(grid.grid_to_world(VALID))
	var valid_hit := battle.mouse_raycaster.get_floor_raycast_result(valid_pixel)
	_check(valid_hit.get("grid_position") == VALID, "The same viewport picks the known valid Depot tile")
	if valid_hit.get("grid_position") == VALID:
		battle._update_movement_preview(valid_hit)
		battle._toggle_destination_inspection()
		await _capture("02-depot-pinned", func(): battle._update_movement_preview(valid_hit))
		battle._toggle_destination_inspection()

func _layered_range() -> void:
	var fixture := RangeFixture.new()
	await fixture.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD, [], true)
	var battle: BattleController = fixture.battle
	var actor: TacticalUnit = fixture.turns.player_units[0]
	var start := Vector3i(6, 0, 15)
	var stairs := Vector3i(6, 3, 12)
	fixture.place(actor, start)
	battle.toggle_move_mode()
	battle._update_movement_preview({"grid_position": stairs})
	_check(battle.query_move(actor, stairs).is_legal() and battle._toggle_destination_inspection(), "A real authored stair destination can be previewed and pinned")
	battle.mouse_raycaster._inspect_level(0.0)
	_check(battle._pinned_destination == BattleController.NO_PREVIEW_CELL and battle._last_tactical_preview.is_empty(),
		"An inspected floor change clears the pin and its text")
	if not capture_dir.is_empty():
		var rig := fixture.level.get_node("CameraRig") as TacticalCamera
		battle.mouse_raycaster._inspect_level(fixture.grid.grid_to_world(stairs).y)
		rig.focus_position((fixture.grid.grid_to_world(start) + fixture.grid.grid_to_world(stairs)) * 0.5)
		rig._manual_pitch = true
		rig.rotation = Vector3(deg_to_rad(-53.0), deg_to_rad(-35.0), 0)
		rig._set_zoom(12.0)
		await physics_frame
		var pixel := rig.camera.unproject_position(fixture.grid.grid_to_world(stairs))
		var hit := battle.mouse_raycaster.get_floor_raycast_result(pixel)
		_check(hit.get("grid_position") == stairs, "Physical ray selects the upper landing")
		if hit.get("grid_position") == stairs:
			battle._update_movement_preview(hit)
			_check(battle._toggle_destination_inspection() and battle.movement_ghost.destination == fixture.grid.grid_to_world(stairs),
				"Pinned upper landing shows its own canonical ghost")
			await _capture("03-range-stairs", func(): battle._update_movement_preview(hit))
	await fixture.dispose(self)

func _push_click(pixel: Vector2) -> void:
	for pressed in [true, false]:
		var input := InputEventMouseButton.new()
		input.button_index = MOUSE_BUTTON_LEFT
		input.pressed = pressed
		input.position = pixel
		root.push_input(input, true)

func _capture(label: String, before_draw: Callable) -> void:
	await RenderingServer.frame_pre_draw
	before_draw.call()
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(capture_dir.path_join(label + ".png")) == OK, "Capture " + label)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
