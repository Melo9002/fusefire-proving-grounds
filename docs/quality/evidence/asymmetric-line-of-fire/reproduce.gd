extends SceneTree
## Reproduces current line-of-fire behavior on the real Depot. Enemy 1 and 2
## cells are reconstruction controls. Enemy 3's cell is in the QA Guard log.

const ALPHA := Vector3i(17, 0, 15)
const ENEMIES: Array[Vector3i] = [Vector3i(21, 0, 21), Vector3i(20, 0, 10), Vector3i(22, 0, 22)]
const SEED := 950507647
var level: BattleLevel
var battle: BattleController
var grid: GridManager
var service: TacticalActionService
var alpha: TacticalUnit
var truck: Node3D
var cargo := AABB()
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.SERVICE_DEPOT)
	config.battle_seed = SEED
	config.player_count = 3
	config.enemy_count = 3
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 3)
	# Preserve this investigation against the incident compiler revision.
	var historical := BattlefieldCatalog.generate(BattlefieldCatalog.SERVICE_DEPOT, Vector2i.ZERO, SEED, 1.0)
	config.content_manifest = historical.content_manifest.duplicate(true)
	config.content_manifest.compiler_revision = 9
	level = load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	await create_timer(0.25).timeout
	if not level.battle_initialization_succeeded:
		push_error("Depot did not initialize")
		quit(2)
		return
	battle = level.battle_controller
	grid = battle.grid_manager
	service = battle.action_service
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	alpha = level.turn_manager.player_units[0]
	var enemies := level.turn_manager.enemy_units.duplicate()
	_place(alpha, ALPHA)
	for index in ENEMIES.size():
		_place(enemies[index], ENEMIES[index])
	var alpha_cell := grid.get_cell_data(ALPHA)
	_check(alpha_cell.world_position.distance_to(Vector3(-2.8513, 0, -4.5)) < 0.0001, "QA canonical standing point")
	_check(SurfaceNavigation.body_clear(grid.map_data, alpha_cell.world_position) and SurfaceNavigation.units_clear(grid, alpha_cell.world_position, alpha_cell.world_position, alpha), "Alpha fits static and live body clearance")
	for shape: Node3D in level.find_children("CargoBody", "Node3D", true, false):
		var size: Vector3 = shape.get_meta("solid_size")
		var bounds := shape.global_transform * AABB(-size * 0.5, size)
		if bounds.grow(0.4).has_point(alpha_cell.world_position):
			truck = shape.get_parent().get_parent()
			cargo = bounds
			break
	if not is_instance_valid(truck):
		push_error("Could not identify the live Truck/CargoBody")
		quit(2)
		return
	print("[Scene] stand=", alpha_cell.world_position, " support=", alpha_cell.support_center, " cover=", alpha_cell.cover_height, " origin=", CombatRules.get_shot_origin(alpha, grid), " cargo=", cargo, " truck=", truck.get_path())
	for enemy: TacticalUnit in enemies:
		_pair(enemy, "original", true)
	_test_boundary(enemies[2])

	var original_faction := alpha.faction
	var turns := level.turn_manager
	var players := turns.player_units.duplicate()
	turns.player_units.assign(enemies)
	turns.enemy_units.assign(players)
	for unit: TacticalUnit in turns.player_units:
		unit.faction = TacticalUnit.Faction.PLAYER
	for unit: TacticalUnit in turns.enemy_units:
		unit.faction = TacticalUnit.Faction.ENEMY
	for enemy: TacticalUnit in enemies:
		_pair(enemy, "exchanged", false)
	turns.player_units.assign(players)
	turns.enemy_units.assign(enemies)
	for unit: TacticalUnit in turns.player_units:
		unit.faction = original_faction
	for unit: TacticalUnit in turns.enemy_units:
		unit.faction = TacticalUnit.Faction.ENEMY
	await _execute(enemies[2])
	await _render(enemies[2])
	await _player_open_control(enemies[2])
	level.queue_free()
	await process_frame
	await process_frame
	print("Asymmetric line of fire audit: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _place(unit: TacticalUnit, cell: Vector3i) -> void:
	_check(grid.can_unit_occupy_cell(unit, cell), "Fixture can occupy %s" % cell)
	grid.update_unit_position(unit, unit.grid_position, cell)
	unit.global_position = grid.grid_to_world(cell) + Vector3.UP * unit.standing_height

func _activate(unit: TacticalUnit) -> void:
	level.turn_manager.current_phase = TurnManager.TurnPhase.PLAYER_TURN if unit.faction == TacticalUnit.Faction.PLAYER else TurnManager.TurnPhase.ENEMY_TURN
	level.turn_manager.active_unit = unit
	unit.stats.set_available_ap_for_setup(3)
	unit.stats.current_supply_points = 4

func _pair(enemy: TacticalUnit, label: String, trace: bool) -> void:
	for actors in [[alpha, enemy], [enemy, alpha]]:
		var shooter: TacticalUnit = actors[0]
		var target: TacticalUnit = actors[1]
		_activate(shooter)
		var query := battle.query_attack(shooter, target)
		var rng_before := service.get_combat_rng_state()
		var revision_before := service.state_revision
		_check(shooter.tactical_state.establish_overwatch(), "Set up query-only Guard reservation")
		var guard := service.query_guard_reaction(shooter, target)
		shooter.tactical_state.clear_overwatch()
		var incoming := shooter != alpha
		_check(query.is_legal() == incoming and guard.can_fire == incoming, "Position controls directed Attack and Guard in " + label)
		_check(service.get_combat_rng_state() == rng_before and service.state_revision == revision_before, "Queries consume no RNG and publish no revision")
		_check(query.visibility_fraction == (0.2 if incoming else 0.0), "Expected body-sample exposure")
		if not incoming:
			_check(query.validation.code == &"blocked_los" and query.blocking_cell == ALPHA and query.evaluation.blocking_bounds.is_equal_approx(cargo), "Outgoing query identifies precise cargo obstacle in source column")
		print("[Query] ", label, " ", shooter.tactical_id, " ", shooter.grid_position, " -> ", target.tactical_id, " ", target.grid_position, " faction=", shooter.faction, " accepted=", query.is_legal(), " code=", query.validation.code, " chance=", query.hit_chance, " exposure=", query.visibility_fraction, " guard=", guard.can_fire, " guard_reason=", guard.reason)
		if trace: _trace(shooter, target)

func _trace(shooter: TacticalUnit, target: TacticalUnit) -> void:
	var origin := CombatRules.get_shot_origin(shooter, grid)
	var base := grid.grid_to_world(target.grid_position)
	var h := target.standing_height
	var delta := base - origin
	var lateral := Vector3(-delta.z, 0, delta.x).normalized() * grid.cell_size * 0.28
	var samples: Array[Vector3] = [base + Vector3.UP * h * 1.2, base + Vector3.UP * h * 1.75, base + Vector3.UP * h * 0.9 + lateral, base + Vector3.UP * h * 0.9 - lateral, base + Vector3.UP * h * 0.5]
	for index in samples.size():
		var sample := samples[index]
		var blocker := CombatRules._get_geometry_between(origin, sample, grid, false, [shooter.grid_position, target.grid_position])
		var reverse_blocker := CombatRules._get_geometry_between(sample, origin, grid, false, [target.grid_position, shooter.grid_position])
		var forward: Variant = cargo.intersects_segment(origin, sample)
		var reverse: Variant = cargo.intersects_segment(sample, origin)
		var mesh: Variant = _truck_hit(origin, sample)
		_check((forward != null) == (reverse != null), "Identical segment intersects cargo in either direction")
		_check((blocker != null) == (forward != null) and (reverse_blocker != null) == (forward != null), "Both segment directions agree with independent cargo intersection")
		_check((mesh != null) == (forward != null), "Visible truck triangles agree on blocked and clear segments")
		print("[Ray] ", shooter.tactical_id, " -> ", target.tactical_id, " sample=", index, " from=", origin, " to=", sample, " blocker=", blocker.grid_position if blocker else null, " entry=", forward, " reverse_entry=", reverse, " mesh_entry=", mesh)

func _truck_hit(origin: Vector3, sample: Vector3) -> Variant:
	var nearest: Variant = null
	var distance := INF
	for instance: MeshInstance3D in truck.find_children("*", "MeshInstance3D", true, false):
		if not instance.is_visible_in_tree() or not instance.mesh: continue
		var transform := instance.global_transform
		var faces := instance.mesh.get_faces()
		for index in range(0, faces.size(), 3):
			var entry: Variant = Geometry3D.segment_intersects_triangle(origin, sample, transform * faces[index], transform * faces[index + 1], transform * faces[index + 2])
			if entry != null and origin.distance_squared_to(entry) < distance:
				nearest = entry
				distance = origin.distance_squared_to(entry)
	return nearest

func _test_boundary(enemy: TacticalUnit) -> void:
	var fa := alpha.grid_position
	for to: Vector3i in [Vector3i(22, 0, 21), Vector3i(22, 0, 22), Vector3i(16, 0, 21)]:
		var launch := CombatRules._evaluate_target_visibility_cells(alpha, fa, enemy, to, grid)
		var return_fire := CombatRules._evaluate_target_visibility_cells(enemy, to, alpha, fa, grid)
		var expected: Vector2i = {Vector3i(22, 0, 21): Vector2i(0, 0), Vector3i(22, 0, 22): Vector2i(0, 1), Vector3i(16, 0, 21): Vector2i(5, 5)}[to]
		_check(Vector2i(launch.visible_count, return_fire.visible_count) == expected, "Nearby blocked, one-way and open controls")
		print("[Neighbor] ", to, " visibility out/in=", launch.visible_count, "/", return_fire.visible_count)
	var tile := grid.get_cell_data(fa)
	var standing := tile.world_position
	for x_shift in [-0.14, -0.10, -0.05, -0.025, 0.0, 0.01, 0.03]:
		tile.world_position = standing + Vector3.RIGHT * x_shift
		var launch := CombatRules._evaluate_target_visibility_cells(alpha, fa, enemy, enemy.grid_position, grid)
		var return_fire := CombatRules._evaluate_target_visibility_cells(enemy, enemy.grid_position, alpha, fa, grid)
		print("[Offset] dx=", x_shift, " same_cell=", grid.world_to_grid(tile.world_position) == fa, " body_clear=", SurfaceNavigation.body_clear(grid.map_data, tile.world_position), " visibility out/in=", launch.visible_count, "/", return_fire.visible_count)
	tile.world_position = standing
	var next_alpha := Vector3i(16, 0, 15)
	var next_stand := grid.grid_to_world(next_alpha)
	var next_out := CombatRules._evaluate_target_visibility_cells(alpha, next_alpha, enemy, enemy.grid_position, grid)
	var next_in := CombatRules._evaluate_target_visibility_cells(enemy, enemy.grid_position, alpha, next_alpha, grid)
	_check(grid.can_unit_occupy_cell(alpha, next_alpha) and SurfaceNavigation.edge_clear(grid.map_data, standing, next_stand), "Neighboring Alpha tile has a supported escape route")
	print("[AlphaNeighbor] ", next_alpha, " stand=", next_stand, " visibility out/in=", next_out.visible_count, "/", next_in.visible_count)
	var enemy_tile := grid.get_cell_data(enemy.grid_position)
	var enemy_standing := enemy_tile.world_position
	var blocked_z := 2.001
	var clear_z := enemy_standing.z
	for iteration in 12:
		var midpoint := (blocked_z + clear_z) * 0.5
		enemy_tile.world_position.z = midpoint
		var samples := CombatRules._evaluate_target_visibility_cells(enemy, enemy.grid_position, alpha, fa, grid)
		if samples.visible_count > 0: clear_z = midpoint
		else: blocked_z = midpoint
	_check(clear_z > 2.001 and clear_z < enemy_standing.z and SurfaceNavigation.body_clear(grid.map_data, enemy_tile.world_position), "Within-cell inbound visibility boundary occurs at a body-clear point")
	print("[Boundary] Enemy3 x=", enemy_standing.x, " z blocked/clear=", blocked_z, "/", clear_z, " cutoff measured with production inset")
	for kind in ["box", "mesh"]:
		var low := 1.5
		var high := enemy_standing.z
		for iteration in 12:
			var mid := (low + high) * 0.5
			var origin := Vector3(enemy_standing.x, enemy.standing_height, mid)
			var bearing := standing - origin
			var outward := Vector3(bearing.z, 0, -bearing.x).normalized()
			var shoulder := standing + outward * 0.28 + Vector3.UP * alpha.standing_height * 0.9
			var entry: Variant = cargo.intersects_segment(origin, shoulder) if kind == "box" else _truck_hit(origin, shoulder)
			if entry == null: high = mid
			else: low = mid
		print("[BoundaryReference] ", kind, " z blocked/clear=", low, "/", high)
	# A known conservative proxy disagreement near the exact encounter. The
	# original z=2.5 pair already proved mesh/box agreement for its ten rays.
	enemy_tile.world_position.z = 2.10
	var boundary_origin := CombatRules.get_shot_origin(enemy, grid)
	var bearing := standing - boundary_origin
	var outer := Vector3(bearing.z, 0, -bearing.x).normalized()
	var shoulder := standing + outer * 0.28 + Vector3.UP * alpha.standing_height * 0.9
	var mesh_hit: Variant = _truck_hit(boundary_origin, shoulder)
	var box_hit: Variant = cargo.intersects_segment(boundary_origin, shoulder)
	var actual := CombatRules.evaluate_attack(enemy, alpha, grid, null)
	_check(SurfaceNavigation.body_clear(grid.map_data, enemy_tile.world_position)
		and not actual.is_legal and box_hit != null and mesh_hit == null,
		"Nearby proxy boundary overblocks a ray past the visible rear taper")
	print("[ProxyControl] origin=", boundary_origin, " shoulder=", shoulder, " box_entry=", box_hit, " mesh_entry=", mesh_hit, " accepted=", actual.is_legal)
	enemy_tile.world_position = enemy_standing
	var probe := CombatRules._evaluate_target_visibility_cells(enemy, enemy.grid_position, alpha, fa, grid)
	var candidate: Vector3 = probe.aim_point
	var distant_origin := CombatRules.get_shot_origin(enemy, grid)
	_check(CombatRules.get_blocking_cell(candidate, distant_origin, grid) == null and CombatRules.get_blocking_cell(CombatRules.get_shot_origin(alpha, grid), candidate, grid) == null, "An outward candidate ray clears geometry; this is a point test only")
	print("[CandidateOrigin] ", candidate, " cross_cell=", grid.world_to_grid(candidate) != fa,
		" reverse_ray_open=true; weapon and pose feasibility untested")
	var angle := alpha.rotation.y
	var before := CombatRules.evaluate_attack(enemy, alpha, grid, null)
	alpha.rotation.y += PI
	var after := CombatRules.evaluate_attack(enemy, alpha, grid, null)
	_check(before.is_legal == after.is_legal and before.aim_point.is_equal_approx(after.aim_point), "View-model yaw does not move authoritative hit samples")
	alpha.rotation.y = angle

func _execute(enemy: TacticalUnit) -> void:
	_activate(alpha)
	var revision := service.state_revision
	var rng := service.get_combat_rng_state()
	var denied := await service.submit_attack(service.make_attack_request(alpha, enemy, TacticalActionRequest.Source.PLAYER), true)
	_check(denied == null and service.last_rejection.code == &"blocked_los" and service.state_revision == revision and service.get_combat_rng_state() == rng and alpha.stats.current_ap == 3 and alpha.stats.current_supply_points == 4, "Player commit rejects the same geometry without spending or drawing")
	alpha.stats.current_hp = 50
	var guard := await service.submit_overwatch(service.make_overwatch_request(alpha, TacticalActionRequest.Source.PLAYER), true)
	_check(guard != null and alpha.tactical_state.is_overwatching, "Real Guard action reserves return fire")
	_activate(enemy)
	var ai := level.enemy_units_parent.get_node("%sAI" % enemy.name) as AIController
	_check(ai._find_attack_target() == alpha, "AI scorer can choose the exposed Alpha")
	_check(await battle.try_aim(enemy), "Enemy resolves actual Aim through authority")
	var query := battle.query_attack(enemy, alpha)
	var controlled_roll := RandomNumberGenerator.new()
	for seed_value in 1000:
		controlled_roll.seed = seed_value
		if controlled_roll.randf() * 100.0 < query.hit_chance:
			service._combat_rng.seed = seed_value
			break
	var receipts := []
	var observe := func(result): receipts.append(result)
	service.action_committed.connect(observe)
	_check(await battle.try_attack(enemy, alpha), "The normal AI attack path commits")
	service.action_committed.disconnect(observe)
	if receipts.is_empty(): return
	var receipt: AttackActionResult = receipts[0]
	_check(receipt.request.source == TacticalActionRequest.Source.AI and receipt.did_hit and receipt.damage == 25 and alpha.stats.current_hp == 25, "Controlled hit reproduces QA damage and source")
	_check(receipt.hit_chance == query.hit_chance and receipt.reaction_events.is_empty() and receipt.guard_checks.get(alpha.tactical_id, {}).get("reason") == "Blocked" and alpha.tactical_state.is_overwatching, "Guard uses its reverse shot geometry and remains reserved")
	print("[Transaction] ", receipt.to_replay_record(), " guard=", receipt.guard_checks)

func _player_open_control(enemy: TacticalUnit) -> void:
	_place(enemy, Vector3i(16, 0, 21))
	_activate(alpha)
	alpha.tactical_state.reset()
	var preview := battle.query_attack(alpha, enemy)
	var receipts := []
	var observe := func(result): receipts.append(result)
	service.action_committed.connect(observe)
	var accepted := await battle.try_attack(alpha, enemy)
	service.action_committed.disconnect(observe)
	_check(preview.is_legal() and accepted and receipts.size() == 1
		and receipts[0].request.source == TacticalActionRequest.Source.PLAYER
		and receipts[0].hit_chance == preview.hit_chance, "Nearby open control commits through the player path with preview chance")
	print("[PlayerControl] ", enemy.grid_position, " chance=", preview.hit_chance, " accepted=", accepted)

func _render(enemy: TacticalUnit) -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute(args[0])
	var rig := level.get_node("CameraRig") as TacticalCamera
	rig.set_process(false)
	rig._cancel_selection_focus()
	var focus := (alpha.global_position + enemy.global_position) * 0.5
	rig.camera.global_position = focus + Vector3(-9, 15, 7) * 1.2
	rig.camera.look_at(focus)
	rig.camera.global_position -= rig.camera.global_basis.x * 1.25
	battle.set_process(false)
	for actors in [[alpha, enemy], [enemy, alpha]]:
		var shooter: TacticalUnit = actors[0]
		var target: TacticalUnit = actors[1]
		_activate(shooter)
		var query := battle.query_attack(shooter, target)
		battle._set_tactical_preview(TacticalFeedbackText.shot(query), TacticalFeedbackText.chance_color(query.hit_chance, query.is_legal()))
		battle.shot_trajectory_visualizer.draw_trajectory(CombatRules.get_shot_origin(shooter, grid), query.aim_point, query.evaluation, true, query.is_legal())
		await create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		var name := "alpha-blocked" if shooter == alpha else "hostile-exposed-sample"
		_check(root.get_texture().get_image().save_png(args[0].path_join(name + ".png")) == OK, "Save rendered tactical screenshot")
