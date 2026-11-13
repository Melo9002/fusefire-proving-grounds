extends SceneTree

const Catalog := preload("res://systems/generation/battlefield_catalog.gd")
const BattleScene := preload("res://levels/prototype_map/prototype_map.tscn")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var plots := {}
	var loading_parcels := {}
	for map_seed in [16, 17, 18, 19]:
		var data := Catalog.generate(Catalog.SERVICE_DEPOT, Vector2i.ZERO, map_seed, 1.0)
		_validate(data, "Depot seed %d" % map_seed)
		var manifest := data.content_manifest
		if not data.generation_errors.is_empty(): continue
		plots[manifest.plot_id] = true
		loading_parcels[manifest.placements[0].parcel_id] = true
		check(manifest.placements.size() == 3, "The depot resolves loading, storage and process parcels")
		var reconstructed := Catalog.generate(Catalog.SERVICE_DEPOT, Vector2i.ZERO, map_seed + 100, 1.0, manifest)
		check(reconstructed.content_manifest == manifest and _signature(reconstructed) == _signature(data), "Exact depot reconstruction owns the seed and placement choices")
	check(plots.size() == 2 and loading_parcels.size() == 2, "Four seeds exercise both authored plots and loading variants")
	_check_depot_shot_bounds()

	var fixed := Catalog.generate(Catalog.TACTICAL_TEST_RANGE, Vector2i.ZERO, 16, 1.0)
	_validate(fixed, "Fixed range")
	var fixed_again := Catalog.generate(Catalog.TACTICAL_TEST_RANGE, Vector2i.ZERO, 17, 1.0)
	check(_signature(fixed) == _signature(fixed_again), "The fixed range keeps terrain, authored deployments and mission cells across seeds")
	check(MissionZonePlanner.has_complete_defaults(fixed), "Every mission preset has an authored zone")
	check(fixed.get_objective_zone(&"reach").has(Vector3i(5, 6, 6)) and fixed.get_objective_zone(&"terminal") == [Vector3i(11, 3, 8)], "Reach and terminal exercise different authored floors")
	var graph := Pathfinder.new()
	MapGraphBuilder.build(fixed, graph)
	for x in [6, 11]:
		check(graph.calculate_3d_path(Vector3i(x, 0, 15), Vector3i(x, 3, 12)).size() == 4, "Authored ramp or stair at X %d has a direct stepped route" % x)
	check(graph.calculate_3d_path(Vector3i(12, 0, 4), Vector3i(12, 3, 5)).size() == 2, "The ladder is an independent route to the control gallery")
	check(graph.calculate_3d_path(Vector3i(7, 3, 9), Vector3i(7, 6, 8)).size() == 2, "The upper ladder connects the two galleries")
	check(fixed.get_cell(Vector3i(7, 0, 7)).can_stop and fixed.get_cell(Vector3i(7, 3, 7)).can_stop and fixed.get_cell(Vector3i(7, 6, 7)).can_stop, "Ground and both decks coexist at the same X/Z")
	var barrier := fixed.get_cell(Vector3i(21, 0, 10))
	check(barrier.cover_type == MapCellData.CoverType.LOW and barrier.walkable and not barrier.can_stop and barrier.movement_cost == 2, "The reaction lane offers directional, vaultable low cover")
	var populations := {}
	var regions := {}
	for map_seed in [16, 17, 18, 19]:
		var populated := Catalog.generate(Catalog.TACTICAL_TEST_RANGE, Vector2i.ZERO, map_seed, 1.0, {"population_enabled": true})
		_validate(populated, "Populated range seed %d" % map_seed)
		if not populated.generation_errors.is_empty(): continue
		var choices: Array = populated.content_manifest.placements[0].population
		populations[str(choices)] = true
		for choice: Dictionary in choices:
			regions[choice.region_id] = true
		for zone_id in MissionZonePlanner.DEFAULT_ZONE_IDS:
			check(populated.get_objective_zone(zone_id) == fixed.get_objective_zone(zone_id), "Population preserves the authored %s zone" % zone_id)
		var exact := Catalog.generate(Catalog.TACTICAL_TEST_RANGE, Vector2i.ZERO, -1, 1.0, populated.content_manifest)
		check(exact.content_manifest == populated.content_manifest and _signature(exact) == _signature(populated), "Range replay reconstructs actual choices without reselection")
	check(populations.size() > 1 and regions.has(&"parking") and regions.has(&"staging"), "Parking and cargo vary through their own authored population regions")

	if _capture_enabled():
		for map_seed in [16, 17]:
			await _capture_depot(map_seed)
	await _play_range()
	print("Compact battlefields: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_depot_shot_bounds() -> void:
	var data := Catalog.generate(Catalog.SERVICE_DEPOT, Vector2i.ZERO, 66566043, 1.0)
	# This regression protects revision 2's sub-cell LOS correction and unchanged
	# movement reservations. Revision 3's intentional shape changes have a separate suite.
	var revision_2 := data.content_manifest.duplicate(true)
	revision_2.compiler_revision = 2
	data = Catalog.generate(Catalog.SERVICE_DEPOT, Vector2i.ZERO, 66566043, 1.0, revision_2)
	var legacy_manifest := data.content_manifest.duplicate(true)
	legacy_manifest.compiler_revision = 1
	var legacy := Catalog.generate(Catalog.SERVICE_DEPOT, Vector2i.ZERO, 66566043, 1.0, legacy_manifest)
	var grid := GridManager.new()
	var floor_mesh := CSGBox3D.new()
	floor_mesh.size = Vector3(40.0, 0.2, 40.0)
	floor_mesh.position.y = -0.1
	root.add_child(floor_mesh)
	grid.map_floor = floor_mesh
	grid.map_data = data
	for lane in [[Vector3i(18, 0, 13), Vector3i(22, 0, 14)], [Vector3i(22, 0, 14), Vector3i(24, 0, 22)]]:
		var origin := grid.grid_to_world(lane[0]) + Vector3.UP
		var target := grid.grid_to_world(lane[1]) + Vector3.UP
		grid.map_data = legacy
		var old_blocker := CombatRules.get_blocking_cell(origin, target, grid)
		check(old_blocker != null, "Recorded depot lane %s reproduces the legacy false obstruction" % [lane])
		grid.map_data = data
		check(CombatRules.get_blocking_cell(origin, target, grid) == null, "Authored LOS volume clears the visible depot lane %s" % [lane])
		if old_blocker:
			check(not data.get_cell(old_blocker.grid_position).can_stop, "Sub-cell LOS keeps the existing movement reservation")
	var across_truck := CombatRules.get_blocking_cell(Vector3(0, 1, -6.5), Vector3(0, 1, -2.5), grid)
	check(across_truck != null and across_truck.authored_shot_bounds.has_volume(), "An actual shot through the truck body remains blocked")
	grid.free()
	floor_mesh.free()

func _capture_depot(map_seed: int) -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.battle_seed = map_seed
	config.select_battlefield(Catalog.SERVICE_DEPOT)
	var level := await _start_battle(config)
	check(level.battle_initialization_succeeded, "Depot seed %d launches a normal battle" % map_seed)
	if level.battle_initialization_succeeded:
		var rig := level.get_node("CameraRig") as TacticalCamera
		rig.set_process(false)
		rig._cancel_selection_focus()
		rig.camera.global_position = Vector3(20, 36, 40) if map_seed == 16 else Vector3(-28, 39, 28)
		rig.camera.look_at(Vector3.ZERO)
		rig.camera.fov = 46.0
		level.get_node("Visualizers/GridVisualizer").hide()
		level.get_node("Visualizers/GridCursor").hide()
		await _capture("service-depot-%d" % map_seed)
	level.queue_free()
	await process_frame

func _play_range() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.battle_seed = 17
	config.ally_count = 5
	config.include_vip = true
	config.select_battlefield(Catalog.TACTICAL_TEST_RANGE)
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.INTERACT_TERMINAL, config.enemy_count)
	var level := await _start_battle(config)
	check(level.battle_initialization_succeeded, "Tactical Test Range launches a normal battle: %s" % [level.battle_initialization_errors])
	if not level.battle_initialization_succeeded:
		level.queue_free()
		return
	check(level.allied_units_parent.has_node("FriendlyVIP") and level.battle_controller.grid_manager.occupancy_map.size() == 10, "Five allies and the VIP spawn in independent legal slots")
	var rig := level.get_node("CameraRig") as TacticalCamera
	rig.set_process(false)
	rig._cancel_selection_focus()
	rig.camera.global_position = Vector3(23, 42, 37)
	rig.camera.look_at(Vector3.ZERO)
	rig.camera.fov = 41.0
	level.get_node("Visualizers/GridVisualizer").hide()
	await _capture("tactical-test-range")
	var actor := level.turn_manager.active_unit
	var grid := level.battle_controller.grid_manager
	var stack := grid.grid_to_world(Vector3i(7, 0, 7))
	rig.camera.global_position = stack + Vector3.UP * 20.0
	rig.camera.look_at(stack, Vector3.FORWARD)
	await physics_frame
	await physics_frame
	var picker := level.get_node("Systems/MouseRaycaster") as MouseRaycaster
	var floors := picker.get_floor_candidates(rig.camera.unproject_position(stack))
	check(floors.map(func(hit: Dictionary) -> int: return hit.grid_position.y) == [6, 3, 0], "The real floor picker sees all three authored surfaces in depth order")
	_place(actor, Vector3i(7, 0, 19), grid)
	rig.camera.global_position = actor.global_position + Vector3(0, 0.25, 5.5)
	rig.camera.look_at(actor.global_position)
	var sedan := level.get_node("GeneratedTerrain/TacticalTestRange/VehicleBay/ReferenceSedan")
	var car_mesh := sedan.find_children("*", "MeshInstance3D", true, false)[0]
	rig._update_camera_occlusion(0.2)
	check(rig._environment_apertures.active.has(car_mesh), "The real selected-unit cutout reveals the actor through the imported reference car")
	var blocker := CombatRules.get_blocking_cell(rig.camera.global_position, actor.global_position, grid)
	check(blocker != null and blocker.grid_position.z in range(21, 24), "Car aperture preserves the tactical shot blocker")
	await _capture("range-vehicle-cutout")
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	actor.movement_speed = 20.0
	_place(actor, Vector3i(12, 0, 4), grid)
	check(await level.battle_controller.try_move(actor, Vector3i(12, 3, 5)), "A normal Move climbs onto the control gallery")
	check(await level.battle_controller.try_move(actor, Vector3i(11, 3, 7)), "A normal Move reaches the authored terminal approach")
	check(await level.battle_controller.try_terminal(actor, &"main_terminal"), "The elevated terminal can be activated through the normal battle action")
	check(level.turn_manager.battle_result == TurnManager.BattleResult.VICTORY, "The authored terminal completes its mission")
	level.queue_free()
	await process_frame

func _start_battle(config: BattleConfiguration) -> BattleLevel:
	var level := BattleScene.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	for frame in 120:
		if level.battle_initialization_succeeded or not level.battle_initialization_errors.is_empty(): break
		await process_frame
	return level

func _place(actor: TacticalUnit, cell: Vector3i, grid: GridManager) -> void:
	grid.update_unit_position(actor, actor.grid_position, cell)
	actor.global_position = grid.grid_to_world(cell) + Vector3.UP * actor.standing_height

func _validate(data: MapData, title: String) -> void:
	check(data.generation_errors.is_empty(), "%s resolves: %s" % [title, data.generation_errors])
	if not data.generation_errors.is_empty(): return
	var graph := Pathfinder.new()
	MapGraphBuilder.build(data, graph)
	var result := MapValidator.validate(data, graph, {TacticalUnit.Faction.PLAYER: 5, TacticalUnit.Faction.ENEMY: 5, TacticalUnit.Faction.ALLY: 6})
	check(result.is_valid(), "%s has connected legal deployments and objectives: %s" % [title, result.describe()])

func _signature(data: MapData) -> int:
	var state := []
	for cell: MapCellData in data.cells.values():
		state.append([cell.grid_position, cell.walkable, cell.can_stop, cell.cover_type, cell.cover_height])
	for zone: MapZoneData in data.zones.values():
		state.append([zone.zone_id, zone.cells])
	for link in data.traversal_links:
		state.append([link.from_cell, link.to_cell])
	return hash(state)

func _capture_enabled() -> bool:
	var args := OS.get_cmdline_user_args()
	return args.size() == 2 and args[0] == "capture" and DisplayServer.get_name() != "headless"

func _capture(view: String) -> void:
	if not _capture_enabled(): return
	var args := OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(args[1])
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(args[1].path_join(view + ".png")) == OK, "Captured %s" % view)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
