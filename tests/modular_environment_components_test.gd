extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var catalog := IndustrialModuleCatalog.create()
	check(catalog.size() == 31, "The modular catalog exposes the original set plus semantic and structural-assembly components")
	check(catalog.industrial_loading_canopy.assembly_enclosure == &"open_shelter", "The catalog distinguishes intentional shelters from incomplete buildings")
	check(catalog.factory_window_wall.module_type == EnvironmentModuleDefinition.ModuleType.WINDOW, "Window sections are explicit module types")
	check(catalog.paved_alley.module_type == EnvironmentModuleDefinition.ModuleType.ALLEY, "Alleys are explicit module types")
	check(catalog.road_crossroad.module_type == EnvironmentModuleDefinition.ModuleType.INTERSECTION, "Road junctions are explicit module types")
	check(catalog.factory_shop_front.module_type == EnvironmentModuleDefinition.ModuleType.SHOP, "Composite shop fronts remain reusable definitions")
	check(catalog.industrial_loading_dock.module_type == EnvironmentModuleDefinition.ModuleType.LOADING_DOCK, "Loading docks are explicit reusable spaces")
	check(catalog.machine_cover_cluster.module_type == EnvironmentModuleDefinition.ModuleType.COVER_CLUSTER, "Machinery cover clusters expose their semantic type")
	check(not catalog.catwalk_stairs.vertical_links.is_empty() and not catalog.maintenance_platform.elevated_surfaces.is_empty(), "Vertical modules carry authored surfaces and links")

	var connection_layout := EnvironmentModuleLayout.new(&"connection_fixture", 1)
	var first := EnvironmentModulePlacement.new(&"road_straight", Vector2i.ZERO, 1)
	var second := EnvironmentModulePlacement.new(&"road_straight", Vector2i(10, 0), 1)
	check(connection_layout.try_add(catalog[first.component_id], first, Vector2i(30, 20)), "First rotated road is legal")
	check(connection_layout.try_add(catalog[second.component_id], second, Vector2i(30, 20)), "Second rotated road is legal")
	check(connection_layout.placements_connect(first, second, catalog), "Quarter-turn rotation preserves compatible road edges")
	var overlap := EnvironmentModulePlacement.new(&"road_straight", Vector2i(9, 0), 1)
	check(not connection_layout.try_add(catalog[overlap.component_id], overlap, Vector2i(30, 20)), "Components on the same placement layer cannot overlap")
	var layered_layout := EnvironmentModuleLayout.new(&"layer_fixture", 2)
	var ground := EnvironmentModulePlacement.new(&"paving_square", Vector2i.ZERO)
	var ground_obstacle := EnvironmentModulePlacement.new(&"cargo_container", Vector2i(2, 2))
	check(layered_layout.try_add(catalog[ground.component_id], ground, Vector2i(20, 20)), "Ground layer placement is legal")
	check(layered_layout.try_add(catalog[ground_obstacle.component_id], ground_obstacle, Vector2i(20, 20)), "Occupant may be placed over an existing ground surface")
	check(not layered_layout.try_add(catalog[ground_obstacle.component_id], EnvironmentModulePlacement.new(&"cargo_container", Vector2i(3, 3)), Vector2i(20, 20)), "Occupants still reject overlap with other occupants")

	var first_map := FlatMapGenerator.generate_modular_industrial_sample(40, 30, 1.0, 7319)
	var second_map := FlatMapGenerator.generate_modular_industrial_sample(40, 30, 1.0, 7319)
	check(first_map.source_kind == ModularIndustrialLayoutBuilder.SOURCE_KIND, "Modular industrial generation is explicit and opt-in")
	check(_signature(first_map) == _signature(second_map), "Identical seed and inputs reproduce the module layout and tactical cells")
	check(first_map.environment_modules.size() == 11, "The sample combines structure, ground, cargo and vaultable components")
	var sample_layout := EnvironmentModuleLayout.new(&"sample_connections", 7319)
	for placement in first_map.environment_modules:
		check(sample_layout.try_add(catalog[placement.component_id], placement, first_map.map_size), "Sample placement remains legal: %s" % placement.component_id)
	check(sample_layout.placements_connect(_find(first_map, &"road_straight"), _find(first_map, &"paving_square"), catalog), "Road edge connects explicitly to the paved frontage")
	check(sample_layout.placements_connect(_find(first_map, &"factory_doorway_wide"), _find(first_map, &"paving_square"), catalog), "Doorway exterior connects explicitly to paving")

	var graph := Pathfinder.new()
	MapGraphBuilder.build(first_map, graph)
	var interior := Vector3i(16, 0, 19)
	var doorway := Vector3i(16, 0, 20)
	var pavement := Vector3i(16, 0, 21)
	check(first_map.get_cell(interior).walkable and first_map.get_cell(doorway).walkable and first_map.get_cell(pavement).walkable, "Entrance clearance remains traversable")
	check(not graph.calculate_3d_path(interior, pavement).is_empty(), "The interior reaches exterior paving through the declared doorway")
	var wall := first_map.get_cell(Vector3i(12, 0, 20))
	check(not wall.walkable and wall.cover_type == MapCellData.CoverType.FULL and wall.blocks_line_of_sight, "Wall module writes authoritative blocking cells")
	var cargo := first_map.get_cell(Vector3i(18, 0, 23))
	check(not cargo.walkable and cargo.cover_type == MapCellData.CoverType.FULL, "Cargo on paving translates its footprint into authoritative cover")
	check(catalog.cargo_container.tactical_role == EnvironmentModuleDefinition.TacticalRole.SOLID_OBSTACLE, "Container semantics explicitly identify a solid tactical obstacle")
	var barrier := first_map.get_cell(Vector3i(13, 0, 23))
	check(barrier.walkable and not barrier.can_stop and barrier.cover_type == MapCellData.CoverType.LOW and barrier.movement_cost == 2, "Vaultable module writes the existing low-cover traversal contract")
	check(catalog.construction_barrier_vault.interaction_at(Vector2i.ZERO) == EnvironmentModuleDefinition.CellInteraction.VAULT, "Vault animation intent is explicit module metadata")
	check(catalog.road_straight.tactical_role == EnvironmentModuleDefinition.TacticalRole.GROUND and catalog.road_straight.cell_effects.is_empty(), "Road visuals remain ordinary tactical ground")
	check(catalog.road_straight.placement_layer == EnvironmentModuleDefinition.PlacementLayer.GROUND and catalog.cargo_container.placement_layer == EnvironmentModuleDefinition.PlacementLayer.OCCUPANT, "Ground and tactical obstacles reserve independent placement layers")
	check(catalog.road_straight.visuals.is_empty() and is_equal_approx(RoadStreetscapeProfile.ROAD_HEIGHT, 0.035) and is_equal_approx(catalog.paving_square.visuals[0].offset.y, 0.02), "Derived roads and imported paving each retain an explicit raised presentation plane")
	check(catalog.factory_wall_corner.visuals[0].yaw_quarters == 0 and catalog.factory_wall_corner.visuals[0].anchor == 1, "Inner corner preserves its authored source orientation and seam")
	check(catalog.factory_wall_straight.size == Vector2i(4, 1) and catalog.factory_doorway_wide.size == Vector2i(4, 1), "Scale-two wall and doorway modules use an integer four-cell rhythm")
	check(catalog.factory_wall_straight.visuals[0].anchor == 1 and catalog.factory_wall_straight.visuals[0].offset == Vector3.ZERO and is_equal_approx(catalog.factory_wall_straight.visuals[0].scale, IndustrialModuleCatalog.STRUCTURE_PRESENTATION_SCALE), "Factory straight pieces preserve their source seam with the presentation-only bleed")
	check(catalog.factory_wall_corner.visuals[0].local_cell == Vector2.ONE and is_equal_approx(catalog.factory_wall_corner.visuals[0].scale, IndustrialModuleCatalog.STRUCTURE_PRESENTATION_SCALE), "Inner corner occupies the intended two-cell integer junction")

	for preset in ModularIndustrialLayoutBuilder.PRESETS:
		var preset_map := FlatMapGenerator.generate_modular_environment_sample(40, 30, 1.0, 4401, preset)
		var repeated_map := FlatMapGenerator.generate_modular_environment_sample(40, 30, 1.0, 4401, preset)
		check(not preset_map.environment_modules.is_empty(), "%s assembles a non-empty modular environment" % preset)
		check(_signature(preset_map) == _signature(repeated_map), "%s is deterministic for identical inputs" % preset)
		var preset_layout := _reconstruct_layout(preset_map, catalog)
		var spawn_candidates := preset_layout.world_suitability_cells(EnvironmentModuleDefinition.Suitability.SPAWN, catalog)
		var objective_candidates := preset_layout.world_suitability_cells(EnvironmentModuleDefinition.Suitability.OBJECTIVE, catalog)
		check(not spawn_candidates.is_empty(), "%s publishes spawn suitability metadata" % preset)
		check(not objective_candidates.is_empty(), "%s publishes objective suitability metadata" % preset)
		if not spawn_candidates.is_empty() and not objective_candidates.is_empty():
			var preset_graph := Pathfinder.new()
			MapGraphBuilder.build(preset_map, preset_graph)
			var validation := MapValidator.validate(preset_map, preset_graph, {TacticalUnit.Faction.PLAYER: 5, TacticalUnit.Faction.ENEMY: 5})
			check(validation.is_valid(), "%s passes general tactical map validation: %s" % [preset, validation.describe()])
			var spawn_cell := preset_map.get_cell(spawn_candidates[0])
			var objective_cell := preset_map.get_cell(objective_candidates[0])
			check(spawn_cell != null and spawn_cell.walkable and spawn_cell.can_stop, "%s spawn candidate resolves to valid tactical ground" % preset)
			check(objective_cell != null and objective_cell.walkable and objective_cell.can_stop, "%s objective candidate resolves to valid tactical ground" % preset)
			if spawn_cell != null and objective_cell != null:
				check(not preset_graph.calculate_3d_path(spawn_cell.grid_position, objective_cell.grid_position).is_empty(), "%s preserves a traversable spawn-to-objective route" % preset)
		var preset_presentation := Node3D.new()
		root.add_child(preset_presentation)
		GeneratedTerrainPresenter.build(preset_map, preset_presentation, 1.0)
		var presented_modules := preset_presentation.get_node_or_null("ModularEnvironment")
		check(presented_modules != null and presented_modules.get_child_count() == preset_map.environment_modules.size(), "%s dispatches every module to the shared presenter" % preset)
		preset_presentation.queue_free()

	var vertical_map := FlatMapGenerator.generate_modular_environment_sample(40, 30, 1.0, 2202, &"vertical_works")
	check(vertical_map.get_cell(Vector3i(11, 2, 12)) != null, "Stairs translate an elevated landing into authoritative MapData")
	check(vertical_map.get_cell(Vector3i(12, 2, 13)) != null, "Platform translates authored elevated surfaces into authoritative MapData")
	check(vertical_map.traversal_links.any(func(link): return link.from_cell == Vector3i(11, 0, 10) and link.to_cell == Vector3i(11, 2, 12)), "Stair metadata creates an authoritative vertical traversal link")
	check(vertical_map.generated_traversals.any(func(link): return link.kind == GeneratedTraversalData.Kind.RAMP), "Ramp metadata preserves its presentation traversal kind")
	var low_connection := EnvironmentModuleConnection.new(Vector2i.ZERO, Vector2i.RIGHT, EnvironmentModuleConnection.Type.VERTICAL, 0)
	var high_connection := EnvironmentModuleConnection.new(Vector2i.ZERO, Vector2i.LEFT, EnvironmentModuleConnection.Type.VERTICAL, 2)
	check(EnvironmentModuleConnection.types_are_compatible(low_connection.type, high_connection.type) and low_connection.elevation != high_connection.elevation, "Vertical connection compatibility remains elevation-aware at placement validation")

	await process_frame
	var presented := Node3D.new()
	root.add_child(presented)
	GeneratedTerrainPresenter.build(first_map, presented, 1.0)
	var modular_root := presented.get_node_or_null("ModularEnvironment")
	check(modular_root != null and modular_root.get_child_count() == first_map.environment_modules.size(), "Presenter creates one visual group per module placement")
	presented.queue_free()
	await process_frame
	var preview = load("res://tools/map_editor.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	var editor_ui := preview.find_child("MapEditorUI", true, false) as Control
	check(editor_ui != null and editor_ui.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Map Editor's transparent UI surface leaves orbit and click selection input available to the 3D view")
	preview._frame_camera()
	check(preview.orbit.focus.is_equal_approx(Vector3(0, 4, 0)), "Preview frames the centered MapData world bounds")
	check(preview.content.get_node_or_null("TacticalGrid") != null, "Preview exposes a grid overlay for visual footprint inspection")
	check("VALID" in preview.status.text, "Preview reports the generated modular layout as valid")
	check(preview._focus_component(&"factory_wall_corner", "factory corner — inner, scale 2.0"), "Map Editor can frame the assembled corner for seam inspection")
	check(preview.inspection_target == "factory corner — inner, scale 2.0" and "Target: factory corner" in preview.status.text, "Map Editor identifies its active inspection target and calibration")
	var selected_module: Node3D = preview.inspection_module
	var selected_meshes := selected_module.find_children("*", "MeshInstance3D", true, false)
	check(not selected_meshes.is_empty() and (selected_meshes[0] as MeshInstance3D).material_overlay != null, "Selected preview module receives a visible outline")
	check("structure-corner-inner.glb" in preview._inspection_transform_text(), "Selection readout identifies the exact imported corner asset")
	var authored_position: Vector3 = selected_module.get_meta("inspection_base_position")
	preview._nudge_inspection(Vector3(0.125, 0.25, -0.5))
	check(selected_module.position.is_equal_approx(authored_position + Vector3(0.125, 0.25, -0.5)), "Preview lets the developer nudge a selected module in three axes")
	check("offset=(0.125, 0.250, -0.500)" in preview._inspection_transform_text(), "Preview reports a copyable authored offset")
	preview._rotate_inspection(90.0)
	check(is_equal_approx(rad_to_deg(selected_module.rotation.y), 90.0), "Preview lets the developer rotate the selected module")
	preview._reset_inspection()
	check(selected_module.position.is_equal_approx(authored_position) and selected_module.rotation.is_equal_approx(Vector3.ZERO), "Preview resets inspection edits to the authored transform")
	var corner_focus: Vector3 = preview.orbit.focus
	preview._set_camera_view(PI * 0.5, 0.18)
	check(preview.orbit.focus.is_equal_approx(corner_focus) and is_equal_approx(preview.orbit.azimuth, PI * 0.5), "View presets preserve the inspection target while changing angle")
	preview._frame_camera()
	preview._set_camera_view(0.0, 1.50)
	var preview_modules: Array[Node] = preview.content.get_node("ModularEnvironment").get_children()
	var cargo_module: Node3D
	for candidate in preview_modules:
		if candidate.get_meta("component_id", &"") == &"cargo_container":
			cargo_module = candidate as Node3D
	var cargo_center: Vector3 = preload("res://presentation/environment_asset_placement.gd").mesh_bounds(cargo_module).get_center()
	var cargo_screen_position: Vector2 = preview.camera.unproject_position(cargo_center)
	var click_camera_focus: Vector3 = preview.orbit.focus
	check(preview._select_module_at_screen(cargo_screen_position), "Preview ray picks a module from its visible screen position")
	check(preview.inspection_module == cargo_module and preview.inspection_target == "cargo_container", "Direct click selection targets the intended module")
	check(preview.orbit.focus.is_equal_approx(click_camera_focus), "Direct click selection preserves the developer's current camera")
	var cargo_meshes := cargo_module.find_children("*", "MeshInstance3D", true, false)
	check(not cargo_meshes.is_empty() and (cargo_meshes[0] as MeshInstance3D).material_overlay != null, "Clicked module receives the selection outline")
	check((selected_meshes[0] as MeshInstance3D).material_overlay == null, "Selecting another module clears the previous outline")
	preview.queue_free()
	await process_frame
	print("Modular environment components: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _signature(data: MapData) -> String:
	var modules: Array[String] = []
	for placement in data.environment_modules:
		modules.append(placement.signature())
	var effects: Array[String] = []
	for cell: MapCellData in data.cells.values():
		if cell.cover_type != MapCellData.CoverType.NONE:
			effects.append("%s:%d:%s:%s" % [cell.grid_position, cell.cover_type, cell.walkable, cell.blocks_line_of_sight])
	modules.sort()
	effects.sort()
	return "%s#%s" % ["|".join(modules), "|".join(effects)]

func _find(data: MapData, id: StringName) -> EnvironmentModulePlacement:
	for placement in data.environment_modules:
		if placement.component_id == id:
			return placement
	return null

func _reconstruct_layout(data: MapData, catalog: Dictionary) -> EnvironmentModuleLayout:
	var layout := EnvironmentModuleLayout.new(&"test_reconstruction", data.environment_module_seed)
	for placement in data.environment_modules:
		check(layout.try_add(catalog[placement.component_id], placement, data.map_size), "Generated placement remains valid during reconstruction: %s" % placement.component_id)
	return layout

func check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
