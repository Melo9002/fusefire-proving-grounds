extends SceneTree
## Invariants: supported fit, swept route, body separation, shared shot/pose point,
## independent source-cell geometry and deterministic reconstructed evidence.
const Compiler = preload("res://systems/generation2/authored_scene_map_compiler.gd")
const Pose = preload("res://presentation/characters/runtime/tactical_pose_context.gd")
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _fixture(revision := 5) -> MapData:
	var data := TacticalMapBuilder.generate(16, 16, 1.0, 17)
	var scene := Node3D.new()
	scene.set_meta("surface_placement_enabled", true)
	var part := Node3D.new()
	part.position = Vector3(1.15, 0.8, 0.5)
	part.set_meta("solid_size", Vector3(1, 1.6, 0.4))
	scene.add_child(part)
	Compiler.compile(scene, data, 1.0, Transform3D.IDENTITY, true, revision)
	SurfaceNavigation.resolve_map(data, 1.0)
	scene.free()
	return data

func _run() -> void:
	var data := _fixture()
	var partial := Vector3i(8, 0, 8)
	var cell := data.get_cell(partial)
	check(data.surface_placement_enabled and cell.can_stop and cell.walkable, "A partly occupied supported floor becomes usable")
	check(cell.world_position.is_equal_approx(Vector3(0.33, 0, 0.5)), "Canonical point fits beside actual face: %s" % cell.world_position)
	check(cell.support_center == Vector3(0.5, 0, 0.5), "Logical support center stays unchanged")
	check(data.shot_obstacles.any(func(p): return p.grid_position.x == partial.x and p.grid_position.z == partial.z), "Source/target-cell geometry has an independent index")
	check(not _fixture(4).get_cell(partial).can_stop, "Historical compiler 4 retains whole-cell reservation")
	check(SurfaceNavigation.signature(data) == SurfaceNavigation.signature(_fixture()), "Same inputs reconstruct identical quantized standing points")
	check(not SurfaceNavigation.supported(data, Vector3(-7.9, 0, 0), data.body_radius), "Body cannot overhang unsupported map edge")
	check(SurfaceNavigation.body_clear(data, cell.world_position), "Resolved body clears actual parts")
	check(not SurfaceNavigation.edge_clear(data, Vector3(0.33, 0, -0.5), Vector3(2.0, 0, 1.5)), "Clear endpoints do not permit sweeping through obstacle")
	check(SurfaceNavigation.edge_clear(data, Vector3(0.33, 0, -0.5), cell.world_position), "Clear route along face remains connected")
	var clear_ground := TacticalMapBuilder.generate(8, 8, 1.0, 17)
	clear_ground.surface_placement_enabled = true
	SurfaceNavigation.resolve_map(clear_ground, 1.0)
	clear_ground.movement_parts.assign([AABB(Vector3(-2, 0, -0.2), Vector3(1.5, 2, 0.4)), AABB(Vector3(0.5, 0, -0.2), Vector3(1.5, 2, 0.4))])
	check(SurfaceNavigation.edge_clear(clear_ground, Vector3(0, 0, -1), Vector3(0, 0, 1)), "A body-sized entrance remains traversable")
	clear_ground.movement_parts[1].position.x = 0.1
	check(not SurfaceNavigation.edge_clear(clear_ground, Vector3(0, 0, -1), Vector3(0, 0, 1)), "A narrow entrance rejects the swept body")
	clear_ground.movement_parts.clear()
	check(not SurfaceNavigation.edge_clear(clear_ground, Vector3(0, 0, 0), Vector3(0, 2, 1)), "Unvalidated multi-level ladder/step cannot teleport a body")
	check(not SurfaceNavigation.edge_clear(clear_ground, Vector3(0, 0, 0), Vector3(0, 1, 1)), "An unsupported rise is rejected rather than treated as a ramp")
	clear_ground.movement_parts.assign([AABB(Vector3(-0.2, 1.5, -0.2), Vector3(0.4, 0.2, 0.4))])
	check(not SurfaceNavigation.edge_clear(clear_ground, Vector3(-1, 0, 0), Vector3(1, 0, 0)), "Swept standing height catches a low beam")
	clear_ground.movement_parts[0].position.y = 2.1
	check(SurfaceNavigation.edge_clear(clear_ground, Vector3(-1, 0, 0), Vector3(1, 0, 0)), "Safe overhead clearance preserves movement")
	var thin := TacticalMapBuilder.generate(16, 16, 1.0, 17)
	var wall := Node3D.new()
	wall.set_meta("surface_placement_enabled", true)
	var wall_part := Node3D.new()
	wall_part.position = Vector3(1, 0.8, 0.5)
	wall_part.set_meta("solid_size", Vector3(0.12, 1.6, 3))
	wall.add_child(wall_part)
	Compiler.compile(wall, thin, 1.0)
	SurfaceNavigation.resolve_map(thin, 1.0)
	wall.free()
	check(thin.get_cell(Vector3i(8, 0, 8)).can_stop and thin.get_cell(Vector3i(9, 0, 8)).can_stop, "A tile-edge wall leaves both adjacent standing cells usable")
	check(not SurfaceNavigation.edge_clear(thin, Vector3(0.5, 0, 0.5), Vector3(1.5, 0, 0.5)), "Usable tiles on both sides do not permit walking through the thin wall")
	var thin_grid := GridManager.new()
	thin_grid.map_data = thin
	check(CombatRules.get_blocking_cell(Vector3(0.5, 1, 0.5), Vector3(1.5, 1, 0.5), thin_grid) != null, "Thin wall blocks shots even when both source/target cells are usable")
	check(CombatRules.get_directional_cover(Vector3i(10, 0, 8), Vector3i(8, 0, 8), thin_grid) == MapCellData.CoverType.FULL, "Thin wall provides directional cover at its real face")
	thin_grid.free()
	var unsupported := data.get_cell(Vector3i(7, 0, 8))
	unsupported.support_surface = false
	check(not SurfaceNavigation.edge_clear(data, Vector3(-1.5, 0, 0.5), cell.world_position), "Missing support blocks a route")
	unsupported.support_surface = true
	var graph := Pathfinder.new()
	MapGraphBuilder.build(data, graph)
	var grid := GridManager.new()
	grid.map_data = data
	root.add_child(grid)
	graph.live_grid = grid
	check(grid.grid_to_world(partial) == cell.world_position, "Runtime movement/presentation uses canonical XYZ")
	var actor := TacticalUnit.new()
	actor.show_world_hud = false
	actor.stats = UnitStats.new()
	actor.add_child(actor.stats)
	actor.name = "SurfaceActor"
	root.add_child(actor)
	check(grid.register_unit(actor, partial), "A supported partial cell can register an actor")
	check(CombatRules.get_shot_origin(actor, grid) == cell.world_position + Vector3.UP * actor.standing_height, "LOS uses committed standing point")
	var contact := Pose.cover_at(grid, partial, Vector3.RIGHT)
	check(contact.type == MapCellData.CoverType.FULL and contact.stand_position == cell.world_position, "Hybrid pose finds own-cell geometry at committed point")
	check(CombatRules.get_blocking_cell(cell.world_position + Vector3.UP, Vector3(2, 1, 0.5), grid) != null, "Own-cell solid still blocks shots")
	check(CombatRules.get_directional_cover(Vector3i(11, 0, 8), partial, grid) == MapCellData.CoverType.FULL, "Actual nearby face protects against incoming fire")
	var overlay := CoverVisualizer.new()
	overlay.grid_manager = grid
	root.add_child(overlay)
	overlay.draw_for_cells([partial])
	check(overlay.full_indicator_count > 0, "Cover overlay finds physical cover in the actor's own cell")
	var vertices: PackedVector3Array = overlay._full_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(absf(vertices[0].x - 0.63) < 0.001, "Cover marker sits beside actual face at .65, not the tile edge")
	overlay.free()
	var other_cell := data.get_cell(Vector3i(7, 0, 8))
	var previous := other_cell.world_position
	other_cell.world_position = cell.world_position - Vector3.RIGHT * 0.4
	var second := TacticalUnit.new()
	second.show_world_hud = false
	second.stats = UnitStats.new()
	second.add_child(second.stats)
	second.faction = TacticalUnit.Faction.ENEMY
	root.add_child(second)
	check(not grid.can_unit_occupy_cell(second, other_cell.grid_position), "Neighboring logical cells cannot overlap bodies")
	check(not grid.register_unit(second, other_cell.grid_position), "Spawn registration rejects neighboring body overlap")
	var controller := BattleController.new()
	controller.grid_manager = grid
	check(not controller.register_mission_unit(second, other_cell.grid_position), "Mission registration also rejects a neighboring-body overlap")
	controller.free()
	other_cell.world_position = previous
	check(grid.register_unit(second, Vector3i(7, 0, 8)), "Separated neighbor is allowed")
	check(not SurfaceNavigation.units_clear(grid, Vector3(-1.5, 0, 0.5), cell.world_position, actor), "Swept route checks other units between endpoints")
	var detour := graph.calculate_path_with_occupancy(Vector3i(6, 0, 8), partial, grid, actor)
	check(detour.size() >= 3 and Array(detour).any(func(point): return not is_equal_approx(point.z, 0.5)), "Occupancy-aware planning finds a safe detour around the neighboring body")
	var safe_detour := not detour.is_empty()
	for index in range(1, detour.size()): safe_detour = safe_detour and SurfaceNavigation.units_clear(grid, detour[index - 1], detour[index], actor)
	check(safe_detour, "Every detour segment, not only the destination, clears other units")
	var attack := CombatRules.evaluate_attack(actor, second, grid, null)
	var preview := CombatRules.evaluate_attack_from_cell(actor, partial, second, grid, null)
	check(attack.is_legal and preview.is_legal and preview.hit_chance == attack.hit_chance and preview.aim_point == attack.aim_point, "Outgoing preview and actual five-sample shot share the resolved point")
	var guard := CombatRules.evaluate_attack_at_cell(second, actor, partial, grid, null)
	var incoming := CombatRules.evaluate_attack(second, actor, grid, null)
	check(guard.is_legal == incoming.is_legal and guard.hit_chance == incoming.hit_chance and guard.aim_point == incoming.aim_point, "Guard checkpoint and live shot use identical resolved target geometry")
	check(CombatRules.has_firing_lane_to_cell(actor, second.grid_position, grid) == attack.is_legal, "Range/Guard coverage agrees with the real unobstructed shot")
	var turn := TurnManager.new()
	root.add_child(turn)
	var fingerprint := BattleStateFingerprint.capture(turn, grid, null)
	cell.world_position.x -= 0.01
	check(fingerprint != BattleStateFingerprint.capture(turn, grid, null), "Within-cell XYZ changes cannot silently pass replay fingerprints")
	cell.world_position.x += 0.01
	for unit: float in [0.5, 1.0, 2.0]:
		for rotation in 4:
			var scaled := TacticalMapBuilder.generate(16, 16, unit, 17)
			var scene := Node3D.new()
			scene.set_meta("surface_placement_enabled", true)
			scene.transform = Transform3D(Basis(Vector3.UP, rotation * PI * 0.5).scaled(Vector3.ONE * unit), Vector3.ZERO)
			var part := Node3D.new()
			part.position = Vector3(1.15, 0.8, 0.5)
			part.set_meta("solid_size", Vector3(1, 1.6, 0.4))
			part.set_meta("precise_shot_bounds", true)
			scene.add_child(part)
			Compiler.compile(scene, scaled, unit)
			SurfaceNavigation.resolve_map(scaled, unit)
			var expected := scene.transform * Vector3(0.33, 0, 0.5)
			check(scaled.cells.values().any(func(value): return value.can_stop and value.world_position.is_equal_approx(expected)), "Compiled standing point follows scale %s, rotation %d" % [unit, rotation])
			scene.free()
	second.free()
	actor.free()
	turn.free()
	grid.free()
	print("Surface navigation: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
