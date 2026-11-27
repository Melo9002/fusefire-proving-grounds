extends SceneTree
## Geometry invariants; no new accuracy/cover balancing is asserted here.
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _beam() -> Node3D:
	var part := Node3D.new()
	part.name = "FloatingBeam"
	part.position = Vector3(0, 2.65, 0)
	part.set_meta("solid_size", Vector3(4, 0.7, 0.4))
	part.set_meta("precise_shot_bounds", true)
	return part

func _run() -> void:
	var floor_mesh := CSGBox3D.new()
	floor_mesh.size = Vector3(12, 0.2, 12)
	floor_mesh.position.y = -0.1
	root.add_child(floor_mesh)
	var grid := GridManager.new()
	grid.map_floor = floor_mesh
	var beam := _beam()
	for turn in 4:
		beam.rotation.y = turn * PI * 0.5
		grid.map_data = TacticalMapBuilder.generate(12, 12, 1, 17)
		AuthoredSceneMapCompiler.compile(beam, grid.map_data, 1)
		var transform := Transform3D(Basis(Vector3.UP, turn * PI * 0.5), Vector3.ZERO)
		var source := transform * Vector3(0, 2.7, -2)
		var target := transform * Vector3(0, 2.7, 2)
		var hit := CombatRules.get_blocking_cell(source, target, grid)
		check(hit != null, "Floating beam blocks raised rays at quarter-turn %d" % turn)
		check(CombatRules.get_blocking_cell(target, source, grid) != null, "Floating beam blocks in reverse at quarter-turn %d" % turn)
		check(CombatRules.get_blocking_cell(transform * Vector3(0, 1, -2), transform * Vector3(0, 1, 2), grid) == null, "Space below the beam remains shootable")
		check(CombatRules.get_blocking_cell(transform * Vector3(0, 3.2, -2), transform * Vector3(0, 3.2, 2), grid) == null, "Space above the beam remains shootable")
		check(grid.map_data.cells.size() == 144, "Shot-only beam adds no tactical surfaces")
		check(grid.map_data.get_cell(Vector3i(6, 0, 6)).can_stop, "Shot-only beam does not reserve ground below it")
		if hit:
			check(hit.authored_shot_bounds.has_point(Vector3(0, 2.7, 0)), "Raised blocker evidence identifies the actual beam height")
	_check_delivery_shot_parts(grid)
	beam.rotation = Vector3.ZERO
	var old := TacticalMapBuilder.generate(12, 12, 1, 17)
	AuthoredSceneMapCompiler.compile(beam, old, 1, Transform3D.IDENTITY, true, 3)
	grid.map_data = old
	check(CombatRules.get_blocking_cell(Vector3(0, 2.7, -2), Vector3(0, 2.7, 2), grid) == null, "Explicit compiler revision 3 retains its historical raised-part result")
	grid.map_data = TacticalMapBuilder.generate(12, 12, 1, 17)
	AuthoredSceneMapCompiler.compile(beam, grid.map_data, 1)
	var graph := Pathfinder.new()
	MapGraphBuilder.build(grid.map_data, graph)
	check(MapValidator.validate(grid.map_data, graph).is_valid(), "Owned raised geometry validates without adding path nodes")
	var raised := grid.map_data.shot_obstacles[0]
	grid.map_data.los_blocking_cells.erase(raised)
	check(MapValidator.validate(grid.map_data, graph).has_code("SHOT_OBSTACLE_NOT_INDEXED"), "Validation rejects missing raised LOS entries")
	grid.map_data.rebuild_los_index()
	var columns := grid.map_data.shot_columns.duplicate()
	grid.map_data.shot_columns.clear()
	check(MapValidator.validate(grid.map_data, graph).has_code("SHOT_OBSTACLE_NOT_INDEXED"), "Validation rejects missing raised column entries")
	grid.map_data.shot_columns = columns
	var orphan := MapCellData.new(Vector3i(5, 2, 5), Vector3.ZERO)
	orphan.is_shot_only = true
	grid.map_data.los_blocking_cells.append(orphan)
	check(MapValidator.validate(grid.map_data, graph).has_code("UNKNOWN_LOS_BLOCKER"), "Validation still rejects an unowned shot-only blocker")
	grid.map_data.rebuild_los_index()
	var far_beam := _beam()
	far_beam.position.z = 2
	AuthoredSceneMapCompiler.compile(far_beam, grid.map_data, 1)
	var nearest := CombatRules.get_blocking_cell(Vector3(0, 2.7, -2), Vector3(0, 2.7, 4), grid)
	var reverse_nearest := CombatRules.get_blocking_cell(Vector3(0, 2.7, 4), Vector3(0, 2.7, -2), grid)
	check(nearest != null and nearest.authored_shot_bounds.get_center().z < 1, "Shot-only index reports the nearest raised part")
	check(reverse_nearest != null and reverse_nearest.authored_shot_bounds.get_center().z > 1, "Reversing the ray selects the other raised part")
	far_beam.free()
	grid.map_data.clear()
	check(grid.map_data.shot_obstacles.is_empty() and grid.map_data.shot_columns.is_empty(), "Clearing a map clears raised geometry and its index")
	# Real actors provide the existing body-height contract without a synthetic actor implementation.
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.TACTICAL_TEST_RANGE)
	config.player_count = 1
	config.enemy_count = 1
	var battle := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	battle.configure_battle(config)
	root.add_child(battle)
	check(battle.battle_initialization_succeeded, "Real range battle accepts current geometry")
	if not battle.battle_initialization_succeeded:
		battle.queue_free()
		grid.free()
		beam.free()
		floor_mesh.queue_free()
		await process_frame
		quit(1)
		return
	var actor: TacticalUnit = battle.turn_manager.player_units[0]
	var enemy: TacticalUnit = battle.turn_manager.enemy_units[0]
	grid.map_data = TacticalMapBuilder.generate(12, 12, 1, 17)
	var from := Vector3i(2, 0, 5)
	var to := Vector3i(9, 0, 5)
	grid.map_data.get_cell(from).world_position.y = 0.35
	grid.map_data.get_cell(to).world_position.y = -0.2
	actor.grid_position = from
	enemy.grid_position = to
	check(is_equal_approx(CombatRules.get_shot_origin(actor, grid).y, 0.35 + actor.standing_height), "Origin uses actual fractional surface height")
	check(is_equal_approx(CombatRules.get_shot_destination(enemy, grid).y, -0.2 + enemy.standing_height), "Destination uses actual lower surface height")
	grid.map_data.get_cell(from).world_position.y = 0
	grid.map_data.get_cell(to).world_position.y = 0
	var wall := grid.map_data.get_cell(Vector3i(6, 0, 5))
	wall.cover_height = 3
	wall.blocks_line_of_sight = true
	wall.cover_type = MapCellData.CoverType.FULL
	grid.map_data.rebuild_los_index()
	var evaluation := CombatRules.evaluate_attack(actor, enemy, grid, battle.get_world_3d())
	check(not evaluation.is_legal and evaluation.blocking_cell == wall, "A fully blocked body reports its blocking wall")
	check(is_equal_approx(evaluation.aim_point.y, enemy.standing_height * 1.2), "Blocked feedback aims along the same first body-sample ray used for blocker evidence")
	enemy.standing_height = 2
	var tall := CombatRules.evaluate_attack(actor, enemy, grid, battle.get_world_3d())
	check(not tall.is_legal and is_equal_approx(tall.aim_point.y, 1.8), "A taller target selects its nearer shoulder sample for coherent blocker evidence")
	enemy.standing_height = 1
	var front_part := AABB(wall.world_position + Vector3(-0.4, 0, -0.4), Vector3(0.2, 3, 0.8))
	wall.authored_shot_parts.assign([front_part, AABB(wall.world_position + Vector3(0.2, 0, -0.4), Vector3(0.2, 3, 0.8))])
	wall.authored_shot_bounds = wall.authored_shot_parts[0].merge(wall.authored_shot_parts[1])
	evaluation = CombatRules.evaluate_attack(actor, enemy, grid, battle.get_world_3d())
	check(evaluation.blocking_bounds == front_part, "Compound blocker evidence selects the first intersected part, not their empty union")
	var visualizer := ShotTrajectoryVisualizer.new()
	visualizer.grid_manager = grid
	root.add_child(visualizer)
	visualizer.set_debug_enabled(true)
	visualizer.draw_trajectory(CombatRules.get_shot_origin(actor, grid), evaluation.aim_point, evaluation, true)
	check(visualizer.blocker_marker.mesh.size.is_equal_approx(front_part.size) and visualizer.blocker_marker.position.is_equal_approx(front_part.get_center()), "Rendered blocker marker consumes the exact intersected part bounds")
	visualizer.queue_free()
	beam.free()
	grid.free()
	floor_mesh.queue_free()
	battle.queue_free()
	await process_frame
	await process_frame
	print("Combat geometry LOS: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _check_delivery_shot_parts(grid: GridManager) -> void:
	var delivery := preload("res://art/environments/authored/objects/delivery.tscn").instantiate() as Node3D
	for turn in 4:
		var rotation := Transform3D(Basis(Vector3.UP, turn * PI * 0.5), Vector3.ZERO)
		var historical := TacticalMapBuilder.generate(12, 12, 1.0, 17)
		AuthoredSceneMapCompiler.compile(delivery, historical, 1.0, rotation, true, 9)
		var current := TacticalMapBuilder.generate(12, 12, 1.0, 17)
		AuthoredSceneMapCompiler.compile(delivery, current, 1.0, rotation)
		check(current.movement_parts == historical.movement_parts, "Cargo quarter-turn %d preserves its movement hulls" % turn)
		grid.map_data = historical
		var upper_from := rotation * Vector3(-1.3, 0.9, -2.0)
		var upper_to := rotation * Vector3(1.3, 0.9, -2.0)
		check(CombatRules.get_blocking_cell(upper_from, upper_to, grid) != null, "Compiler 9 keeps the old cargo obstruction")
		grid.map_data = current
		check(CombatRules.get_blocking_cell(upper_from, upper_to, grid) == null
			and CombatRules.get_blocking_cell(upper_to, upper_from, grid) == null, "Cleared rear taper stays open in both directions")
		check(CombatRules.get_blocking_cell(rotation * Vector3(-1.3, 0.5, -2.0), rotation * Vector3(1.3, 0.5, -2.0), grid) != null,
			"The lower overhang remains solid")
		check(CombatRules.get_blocking_cell(rotation * Vector3(-1.3, 0.9, -1.85), rotation * Vector3(1.3, 0.9, -1.85), grid) != null,
			"The cargo core remains solid")
	delivery.free()
