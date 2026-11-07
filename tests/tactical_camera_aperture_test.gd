extends SceneTree
## Optional rendered inspection with -- capture <output-directory>.

const BattleScene = preload("res://levels/prototype_map/prototype_map.tscn")
const Catalog = preload("res://systems/generation/battlefield_catalog.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var output := args[1] if args.size() == 2 and args[0] == "capture" else ""
	if not output.is_empty() and DisplayServer.get_name() == "headless":
		push_error("Capture requires a renderer")
		quit(1)
		return
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(Catalog.PARKING_GARAGE)
	config.battle_seed = 17
	config.player_count = 2
	config.enemy_count = 1
	config.content_manifest = {"population_enabled": false}
	var level := BattleScene.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	await process_frame
	await process_frame
	if not level.battle_initialization_succeeded:
		push_error("Garage battle initialization failed: %s" % [level.battle_initialization_errors])
		quit(1)
		return
	var rig := level.get_node("CameraRig") as TacticalCamera
	rig.set_process(false)
	rig._cancel_selection_focus()
	var grid := level.battle_controller.grid_manager
	var raycaster := level.get_node("Systems/MouseRaycaster") as MouseRaycaster
	var actor := level.turn_manager.player_units[0]
	var other := level.turn_manager.player_units[1]
	var enemy := level.turn_manager.enemy_units[0]
	var column := level.find_child("WestColumn1", true, false) as TacticalCameraAperture
	var next_column := level.find_child("WestColumn2", true, false) as TacticalCameraAperture
	var wall := level.find_child("ServiceBoundary", true, false) as TacticalCameraAperture
	var deck := level.find_child("UpperDeck", true, false) as WarehouseRoofCutaway
	_place(actor, Vector3i(7, 0, 9), grid)
	_place(other, Vector3i(7, 0, 16), grid)
	_place(enemy, Vector3i(3, 0, 9), grid)
	level.turn_manager.active_unit = actor
	enemy.attack_range = 8
	var before := CombatRules.evaluate_attack(enemy, actor, grid, level.get_world_3d())
	_check(not before.is_legal and before.blocking_cell == grid.get_cell_data(Vector3i(5, 0, 9)), "The real column blocks a legal-range shot before the aperture")

	rig.camera.fov = 38
	_view(rig, actor.global_position + Vector3(-9, 0.7, 0), actor.global_position)
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		level.get_node("Visualizers/GridVisualizer").hide()
		enemy.hide()
		rig._update_camera_occlusion(0.0)
		await _capture(output, "column-closed")
	rig._update_camera_occlusion(0.05)
	_check(column.strength > 0.0 and column.strength < 1.0, "Occlusion starts a gradual aperture")
	rig._update_camera_occlusion(0.2)
	_check(column.strength == 1.0 and next_column.strength == 0.0 and wall.strength == 0.0, "Only the obstructing column opens")
	_check((column.get_node("SafetyBand") as TacticalCameraAperture).strength == 1.0, "The safety band opens with its column")
	_check(not deck.visible, "Whole-deck cutaway continues to expose the lower floor")
	if not output.is_empty():
		await _capture(output, "column-open")
		enemy.show()
	var after := CombatRules.evaluate_attack(enemy, actor, grid, level.get_world_3d())
	_check(not after.is_legal and after.blocking_cell == before.blocking_cell and after.cover_type == before.cover_type, "Opening preserves authoritative cover, LOS and targeting")
	_check(grid.get_unit_at(actor.grid_position) == actor and not grid.can_unit_occupy_cell(actor, Vector3i(5, 0, 9)), "Opening preserves unit occupancy and blocked movement")

	level.turn_manager.active_unit = other
	_view(rig, other.global_position + Vector3(-9, 0.7, 0), other.global_position)
	rig._update_camera_occlusion(0.05)
	_check(column.strength > 0.0 and column.strength < 1.0, "Changing selection starts closing the old opening")
	rig._update_camera_occlusion(0.2)
	_check(column.strength == 0.0, "A clear sightline restores the previous column")

	# The garage needs an actual pick surface for player-issued upstairs moves.
	var aisle := Vector3i(16, 4, 19)
	var aisle_world := grid.grid_to_world(aisle)
	_view(rig, aisle_world + Vector3(0, 20, 0.5), aisle_world)
	await physics_frame
	await physics_frame
	var screen_point := rig.camera.unproject_position(aisle_world)
	_check(raycaster.get_floor_candidates(screen_point).any(func(hit): return hit.grid_position == aisle), "Mouse ray can pick the authored upper aisle")
	raycaster._inspect_level(4.0)
	rig._update_camera_occlusion(0.2)
	_check(deck.visible and raycaster.get_floor_raycast_result(screen_point).get("grid_position") == aisle, "Upper floor inspection shows and selects the upper deck")
	raycaster._inspect_level(0.0)
	rig._update_camera_occlusion(0.2)
	_check(not deck.visible and raycaster.get_floor_raycast_result(screen_point).get("grid_position", Vector3i.UP).y == 0, "Ground inspection hides the deck and selects the ground below")
	_place(other, aisle, grid)
	rig._update_camera_occlusion(0.2)
	_check(deck.visible and is_equal_approx(rig.inspected_floor_height(), 4.0), "An elevated selection restores the deck after the inspected floor is left")

	_place(actor, Vector3i(7, 0, 25), grid)
	level.turn_manager.active_unit = actor
	_view(rig, Vector3(-24, 4.4, 36), actor.global_position)
	rig._update_camera_occlusion(0.2)
	_check(wall.strength == 1.0, "An explicitly authored visual-only boundary wall can open")
	if not output.is_empty():
		await _capture(output, "background-wall-open")
	rig._cinematic_active = true
	rig._cinematic_look_target = actor.global_position
	rig._update_camera_occlusion(0.2)
	_check(wall.strength == 0.0, "Cinematic framing closes tactical apertures")
	if not output.is_empty():
		await _capture(output, "background-wall-closed")
	rig._cinematic_active = false
	level.battle_controller.replay_mode = true
	rig._update_camera_occlusion(0.2)
	_check(wall.strength == 0.0, "Replay camera ownership leaves the tactical aperture closed")
	level.battle_controller.replay_mode = false
	actor.hide()
	rig._update_camera_occlusion(0.2)
	_check(wall.strength == 0.0 and not actor.is_visible_in_tree(), "A hidden unit cannot open the aperture")
	actor.show()
	rig._update_camera_occlusion(0.2)
	_check(wall.strength == 1.0, "The friendly focus can reopen the wall")
	raycaster._inspect_level(0.0)
	rig._update_camera_occlusion(0.2)
	_check(wall.strength == 0.0, "Manual floor inspection closes the unit aperture")
	_place(actor, Vector3i(7, 0, 24), grid)
	_view(rig, Vector3(-24, 4.4, 36), actor.global_position)
	rig._update_camera_occlusion(0.2)
	_check(wall.strength == 1.0, "Moving the selected unit clears manual inspection and restores its camera focus")
	rig.free()
	_check(wall.strength == 0.0, "Removing the camera restores the scene's solid appearance")
	level.queue_free()
	await process_frame
	print("Tactical camera aperture: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _place(unit: TacticalUnit, cell: Vector3i, grid: GridManager) -> void:
	_check(grid.can_unit_occupy_cell(unit, cell), "Fixture unit can stand at %s" % cell)
	grid.update_unit_position(unit, unit.grid_position, cell)
	unit.global_position = grid.grid_to_world(cell) + Vector3.UP * unit.standing_height

func _view(rig: TacticalCamera, eye: Vector3, subject: Vector3) -> void:
	rig.camera.global_position = eye
	rig.camera.look_at(subject)

func _capture(output: String, name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(output.path_join("garage-aperture-%s.png" % name)) == OK, "Capture saved for %s" % name)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
