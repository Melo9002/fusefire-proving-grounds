extends SceneTree
## Explicit GPU evidence for Task 6.2. Automated gameplay assertions live in
## generation_2_tactical_gameplay_test.gd; these images support visual review.

const CAPTURE_SIZE := Vector2i(1600, 900)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		push_error("A rendered window and output directory are required.")
		quit(1)
		return
	var output: String = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size = CAPTURE_SIZE
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.battlefield_preset = BattleConfiguration.BattlefieldPreset.GENERATION_2_INDUSTRIAL
	config.map_size = BattleConfiguration.GENERATION_2_MAP_SIZE
	config.battle_seed = 17
	config.player_count = 2
	config.enemy_count = 2
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.INTERACT_TERMINAL, 2, false)
	var battle := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	battle.configure_battle(config)
	var completed: Array = []
	battle.battle_initialization_finished.connect(func(success: bool, errors: Array): completed.append({"success": success, "errors": errors}), CONNECT_ONE_SHOT)
	root.add_child(battle)
	var deadline := Time.get_ticks_msec() + 45000
	while completed.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	if completed.is_empty() or not completed[0].success:
		push_error("Generation 2.0 tactical capture initialization failed: %s" % str(completed))
		quit(1)
		return
	var rig := battle.get_node("CameraRig") as TacticalCamera
	rig.focus_position(Vector3.ZERO)
	rig._set_zoom(56.0)
	await process_frame
	await RenderingServer.frame_post_draw
	if not _save(output.path_join("generation-2-seed-17-normal.png")): return

	var structure_focus := _first_structure_focus(battle.active_generated_map)
	if structure_focus != Vector3.INF:
		rig.focus_position(structure_focus)
		rig._set_zoom(36.0)
		await process_frame
		await RenderingServer.frame_post_draw
		if not _save(output.path_join("generation-2-seed-17-frontage.png")): return

	rig.focus_position(Vector3.ZERO)
	rig._set_zoom(56.0)
	var tools := battle.get_node("Visualizers/BattleUI/DebugTools") as DebugTools
	await process_frame
	var inspector = tools._map_inspector
	inspector.set_zones_visible(true)
	inspector.set_inspection_enabled(true)
	var stoppable: Array[Vector3i] = []
	for cell: MapCellData in battle.active_generated_map.cells.values():
		if cell.walkable and cell.can_stop: stoppable.append(cell.grid_position)
	battle.battle_controller.cover_visualizer.draw_for_cells(stoppable)
	await process_frame
	await RenderingServer.frame_post_draw
	if not _save(output.path_join("generation-2-seed-17-tactical-overlay.png")): return
	print("Generation 2.0 tactical captures saved to " + output)
	quit()

func _first_structure_focus(data: MapData) -> Vector3:
	var catalog := IndustrialModuleCatalog.create()
	for placement: EnvironmentModulePlacement in data.environment_modules:
		var definition: EnvironmentModuleDefinition = catalog.get(placement.component_id)
		if definition and not definition.structural_assembly_id.is_empty():
			var center := placement.origin + definition.rotated_size(placement.rotation) / 2
			var cell := data.get_cell(Vector3i(center.x, placement.elevation, center.y))
			if cell: return cell.world_position
	return Vector3.INF

func _save(path: String) -> bool:
	var error := root.get_texture().get_image().save_png(path)
	if error == OK: return true
	push_error("Generation 2.0 tactical capture failed: %s" % error)
	quit(1)
	return false
