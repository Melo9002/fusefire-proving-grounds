extends SceneTree

const BATTLE_SCENE := preload("res://levels/prototype_map/prototype_map.tscn")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _test_eliminate_battle()
	await _test_terminal_battle()
	_test_unsatisfiable_deployment_rejection()
	print("Generation 2.0 tactical gameplay: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_eliminate_battle() -> void:
	var level := await _start_battle(MissionObjectiveDefinition.Kind.ELIMINATE, 2, 1)
	if level == null: return
	var battle: BattleController = level.battle_controller
	var grid: GridManager = battle.grid_manager
	var data: MapData = grid.map_data
	var turns: TurnManager = level.turn_manager
	var players: Array[TacticalUnit] = turns.player_units
	var enemy: TacticalUnit = turns.enemy_units[0]

	check(battle.last_map_validation != null and battle.last_map_validation.is_valid(), "Generation 2.0 starts with a valid authoritative tactical map")
	check(_deployments_are_legal(data, players + turns.enemy_units, grid), "every requested unit occupies a unique legal document deployment cell")
	check(data.traversal_links.is_empty(), "the current Generation 2.0 industrial grammar makes no unsupported elevation-link claim")
	check(_all_default_zones_documented(level), "runtime mission zones, document mission context, and early reservations agree")
	check(_has_path_to_zone(data, battle.pathfinder, TacticalUnit.Faction.PLAYER, &"reach") and _has_path_to_zone(data, battle.pathfinder, TacticalUnit.Faction.PLAYER, &"extract") and _has_path_to_zone(data, battle.pathfinder, TacticalUnit.Faction.PLAYER, &"rescue_spawn") and _has_path_to_zone(data, battle.pathfinder, TacticalUnit.Faction.ENEMY, &"enemy_extract"), "Reach, rescue, and both extraction objectives have authoritative routes from their owning deployments")
	check(_has_reachable_functional_access(level), "a certified parcel access region remains reachable from player deployment in authoritative MapData")
	check(_has_consistent_presented_structure(level), "one imported building placement, its authored tactical footprint, and its presented transform share the same document placement")

	var active: TacticalUnit = turns.active_unit
	var movement: MoveQueryResult = battle.action_service.query_move(active.tactical_id)
	var destination: Vector3i = _first_road_destination(movement.legal_destination_cells, data)
	if destination.x < 0 and not movement.legal_destination_cells.is_empty(): destination = movement.legal_destination_cells[0]
	check(destination.x >= 0, "an active unit has a reachable Generation 2.0 movement destination")
	if destination.x >= 0:
		var start: Vector3i = grid.get_unit_grid(active)
		var moved: MoveActionResult = await battle.action_service.submit_move(battle.action_service.make_move_request(active, destination, TacticalActionRequest.Source.PLAYER), true)
		check(moved != null and moved.start_cell == start and moved.target_cell == destination and grid.get_unit_at(destination) == active, "movement commits through the real action service and MapData path")
	var blocked: Vector3i = _first_blocked_cell(data)
	if blocked.x >= 0:
		var revision := battle.action_service.state_revision
		var ap_before := active.stats.current_ap
		var invalid: MoveQueryResult = battle.action_service.query_move(active.tactical_id, blocked)
		check(not invalid.is_legal() and battle.action_service.state_revision == revision and active.stats.current_ap == ap_before, "an unreachable building or obstacle cell is rejected without mutating tactical state")

	var blocker_case: Dictionary = _find_blocked_los_case(data)
	check(not blocker_case.is_empty(), "the generated battlefield contains an authored full-cover LOS case")
	if not blocker_case.is_empty():
		_relocate(grid, active, blocker_case.attacker)
		_relocate(grid, enemy, blocker_case.target)
		active.attack_range = 20
		var blocked_shot := CombatRules.evaluate_attack(active, enemy, grid, active.get_world_3d())
		check(not blocked_shot.is_legal and blocked_shot.blocking_cell != null and blocked_shot.blocking_cell.grid_position == blocker_case.blocker, "authored full cover blocks LOS at the expected compiled cell")
	var cover_case: Dictionary = _find_low_cover_case(data)
	check(not cover_case.is_empty(), "the generated battlefield contains an authored directional-cover case")
	if not cover_case.is_empty():
		_relocate(grid, active, cover_case.attacker)
		_relocate(grid, enemy, cover_case.target)
		active.attack_range = 20
		var covered_shot := CombatRules.evaluate_attack(active, enemy, grid, active.get_world_3d())
		check(covered_shot.is_legal and covered_shot.cover_type == MapCellData.CoverType.LOW and covered_shot.hit_chance <= 50, "directional cover comes from the authored MapData cell and affects the real combat query")

	# A real Wait action advances the active-unit queue on this generated map.
	players[0].stats.set_available_ap_for_setup(players[0].stats.max_ap)
	if turns.active_unit != players[0]: turns.call("_set_active_unit", players[0])
	var waited: SimpleActionResult = await battle.action_service.submit_simple(battle.action_service.make_simple_request(&"wait", players[0], TacticalActionRequest.Source.PLAYER), true)
	await process_frame
	check(waited != null and turns.active_unit == players[1], "a committed gameplay action advances the player activation queue normally")

	# Complete Eliminate through the authoritative attack transaction. Fixture
	# setup controls only positions/HP; objective progress is never written here.
	var pair: Dictionary = _first_clear_pair(data, grid)
	check(not pair.is_empty(), "a clear adjacent combat pair exists on the generated map")
	if not pair.is_empty():
		_relocate(grid, players[1], pair.first)
		_relocate(grid, enemy, pair.second)
		players[1].attack_range = 20
		players[1].stats.set_available_ap_for_setup(players[1].stats.max_ap)
		enemy.stats.current_hp = 1
		var attack_query: AttackQueryResult = battle.action_service.query_attack(players[1].tactical_id, enemy.tactical_id)
		check(attack_query.is_legal() and attack_query.hit_chance == 100, "the mission-finishing attack is a legal guaranteed gameplay action (%s, %d%%)" % [attack_query.reason, attack_query.hit_chance])
		var attack: AttackActionResult = await battle.action_service.submit_attack(battle.action_service.make_attack_request(players[1], enemy, TacticalActionRequest.Source.PLAYER), true)
		await process_frame
		var objective = level.objective_manager.get_objective(&"eliminate")
		check(attack != null and attack.did_hit and attack.target_defeated, "the authoritative combat transaction defeats the mission target")
		check(objective != null and objective.is_completed() and turns.battle_result == TurnManager.BattleResult.VICTORY and turns.current_phase == TurnManager.TurnPhase.TRANSITION, "Eliminate reaches a legitimate mission victory and stops normal turn progression")
	level.queue_free()
	await process_frame
	await process_frame

func _test_terminal_battle() -> void:
	var level := await _start_battle(MissionObjectiveDefinition.Kind.INTERACT_TERMINAL, 1, 1)
	if level == null: return
	var battle: BattleController = level.battle_controller
	var grid: GridManager = battle.grid_manager
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var terminal = level.objective_manager.get_terminal_state(&"main_terminal")
	check(terminal != null, "the Generation 2.0 terminal mission resolves its document-owned terminal zone")
	if terminal:
		var terminal_cell: Vector3i = terminal.definition.grid_position
		var approach: Vector3i = _legal_terminal_approach(grid, terminal_cell)
		var spawn: Vector3i = grid.get_unit_grid(actor)
		var full_path: PackedVector3Array = battle.pathfinder.calculate_3d_path(spawn, approach) if approach.x >= 0 else PackedVector3Array()
		check(approach.x >= 0 and not full_path.is_empty(), "the deployed squad has an authoritative path to a legal terminal approach")
		if approach.x >= 0:
			_relocate(grid, actor, approach)
			actor.stats.set_available_ap_for_setup(actor.stats.max_ap)
			var query := battle.query_terminal(actor, &"main_terminal")
			check(query.is_legal(), "terminal interaction is legal from the reachable approach cell")
			var result: MissionActionResult = await battle.action_service.submit_mission(battle.action_service.make_terminal_request(actor, &"main_terminal", TacticalActionRequest.Source.PLAYER), true)
			await process_frame
			var objective = level.objective_manager.get_objective(&"activate_terminal")
			check(result != null and result.terminal_activated_after and objective != null and objective.is_completed(), "the real mission action activates the terminal and completes its objective")
			check(level.turn_manager.battle_result == TurnManager.BattleResult.VICTORY, "terminal completion produces the supported mission victory state")
	level.queue_free()
	await process_frame
	await process_frame

func _test_unsatisfiable_deployment_rejection() -> void:
	var config := _config(2, 1)
	var built := Generation2BattlefieldBuilder.build(config)
	check(built.ok, "the deterministic Generation 2.0 document builds before the rejection fixture is applied")
	if not built.ok: return
	var document := BattlefieldLayoutDocument.from_dictionary(built.document.to_dictionary())
	for zone in document.mission_context.get("zones", []):
		if int(zone.get("kind", -1)) == MapZoneData.Kind.DEPLOYMENT and int(zone.get("faction", -1)) == TacticalUnit.Faction.PLAYER:
			zone["cells"] = zone.get("cells", []).slice(0, 1)
			break
	var result := Generation2BattlefieldBuilder.compile_document(document, config)
	check(not result.ok and result.errors.any(func(error): return error.get("code", "") == "INSUFFICIENT_DEPLOYMENT"), "unsatisfiable required deployment fails explicitly before a battle can become playable")

func _start_battle(mission_kind: int, player_count: int, enemy_count: int) -> BattleLevel:
	var config := _config(player_count, enemy_count)
	config.mission = MissionCatalog.create_mission(mission_kind, enemy_count, false)
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	level.configure_battle(config)
	var completed: Array = []
	level.battle_initialization_finished.connect(func(success: bool, errors: Array): completed.append({"success": success, "errors": errors.duplicate(true)}), CONNECT_ONE_SHOT)
	root.add_child(level)
	var deadline := Time.get_ticks_msec() + 45000
	while completed.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	var ok: bool = not completed.is_empty() and bool(completed[0].success)
	check(ok, "%s initializes through the real Generation 2.0 battle path: %s" % [MissionCatalog.PRESETS[mission_kind].title, str(completed[0].errors if not completed.is_empty() else "timeout")])
	if not ok:
		level.queue_free()
		await process_frame
		return null
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	return level

func _config(player_count: int, enemy_count: int) -> BattleConfiguration:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.battlefield_preset = BattleConfiguration.BattlefieldPreset.GENERATION_2_INDUSTRIAL
	config.map_size = BattleConfiguration.GENERATION_2_MAP_SIZE
	config.battle_seed = 17
	config.player_count = player_count
	config.enemy_count = enemy_count
	return config

func _deployments_are_legal(data: MapData, units: Array, grid: GridManager) -> bool:
	var occupied: Array[Vector3i] = []
	for unit: TacticalUnit in units:
		var cell := grid.get_unit_grid(unit)
		var faction_spawns := data.get_spawn_cells(unit.faction)
		var cell_data := data.get_cell(cell)
		if cell not in faction_spawns or cell in occupied or cell_data == null or not cell_data.walkable or not cell_data.can_stop: return false
		occupied.append(cell)
	return true

func _all_default_zones_documented(level: BattleLevel) -> bool:
	var document_ids: Array[String] = []
	for zone in level.active_battlefield_document.mission_context.get("zones", []): document_ids.append(str(zone.get("zone_id", "")))
	var owners: Array[String] = []
	for reservation in level.active_battlefield_document.spatial_layout.get("reservations", []): owners.append(str(reservation.get("owner_ref", "")))
	for zone_id in MissionZonePlanner.DEFAULT_ZONE_IDS:
		if level.active_generated_map.get_objective_zone(zone_id).is_empty() or String(zone_id) not in document_ids or "zone:%s" % zone_id not in owners: return false
	return true

func _has_reachable_functional_access(level: BattleLevel) -> bool:
	var data: MapData = level.active_generated_map
	var spawn_cells := data.get_spawn_cells(TacticalUnit.Faction.PLAYER)
	if spawn_cells.is_empty(): return false
	for relationship in level.active_battlefield_document.relationships:
		if relationship.get("kind", "") not in ["pedestrian_access", "loading_access", "service_clearance"]: continue
		for encoded in relationship.get("properties", {}).get("access_cells", []):
			if not encoded is Array or encoded.size() != 2: continue
			var access := Vector3i(int(encoded[0]), 0, int(encoded[1]))
			var cell := data.get_cell(access)
			if cell and cell.walkable and cell.can_stop and not level.battle_controller.pathfinder.calculate_3d_path(spawn_cells[0], access).is_empty(): return true
	return false

func _has_path_to_zone(data: MapData, graph: Pathfinder, faction: TacticalUnit.Faction, zone_id: StringName) -> bool:
	var origins := data.get_spawn_cells(faction)
	var targets := data.get_objective_zone(zone_id)
	for origin in origins:
		for target in targets:
			if origin == target or not graph.calculate_3d_path(origin, target).is_empty(): return true
	return false

func _has_consistent_presented_structure(level: BattleLevel) -> bool:
	var data: MapData = level.active_generated_map
	var catalog := IndustrialModuleCatalog.create()
	var presented := level.get_node_or_null("GeneratedTerrain/ModularEnvironment")
	if presented == null: return false
	for index in data.environment_modules.size():
		var placement: EnvironmentModulePlacement = data.environment_modules[index]
		var definition: EnvironmentModuleDefinition = catalog.get(placement.component_id)
		if definition == null or definition.structural_assembly_id.is_empty() or definition.cell_effects.is_empty(): continue
		var tactical_matches := true
		for local_cell: Vector2i in definition.cell_effects:
			var rotated := definition.rotate_cell(local_cell, placement.rotation)
			var world := Vector3i(placement.origin.x + rotated.x, placement.elevation, placement.origin.y + rotated.y)
			var actual := data.get_cell(world)
			var expected: Dictionary = definition.cell_effects[local_cell]
			if actual == null or actual.walkable != bool(expected.get("walkable", true)) or actual.can_stop != bool(expected.get("can_stop", expected.get("walkable", true))) or actual.blocks_line_of_sight != bool(expected.get("blocks_los", false)):
				tactical_matches = false
				break
		if not tactical_matches: continue
		for node in presented.get_children():
			if int(node.get_meta("placement_index", -1)) == index:
				return node.get_meta("component_id", &"") == placement.component_id and node.get_meta("origin", Vector2i(-1, -1)) == placement.origin and int(node.get_meta("rotation", -1)) == placement.rotation and node.get_child_count() > 0
	return false

func _first_road_destination(cells: Array[Vector3i], data: MapData) -> Vector3i:
	var road_cells: Dictionary[Vector3i, bool] = {}
	var catalog := IndustrialModuleCatalog.create()
	for placement: EnvironmentModulePlacement in data.environment_modules:
		var definition: EnvironmentModuleDefinition = catalog.get(placement.component_id)
		if definition and definition.module_type in [EnvironmentModuleDefinition.ModuleType.ROAD, EnvironmentModuleDefinition.ModuleType.INTERSECTION]:
			for cell: Vector2i in EnvironmentModuleLayout.new().world_cells(definition, placement): road_cells[Vector3i(cell.x, placement.elevation, cell.y)] = true
	for cell in cells:
		if road_cells.has(cell): return cell
	return Vector3i(-1, -1, -1)

func _first_blocked_cell(data: MapData) -> Vector3i:
	for cell: MapCellData in data.cells.values():
		if not cell.walkable or not cell.can_stop: return cell.grid_position
	return Vector3i(-1, -1, -1)

func _find_blocked_los_case(data: MapData) -> Dictionary:
	for blocker: MapCellData in data.cells.values():
		if not blocker.blocks_line_of_sight: continue
		for direction in [Vector3i.RIGHT, Vector3i.BACK]:
			var first := data.get_cell(blocker.grid_position - direction)
			var second := data.get_cell(blocker.grid_position + direction)
			if first and second and first.walkable and first.can_stop and second.walkable and second.can_stop:
				return {"attacker": first.grid_position, "blocker": blocker.grid_position, "target": second.grid_position}
	return {}

func _find_low_cover_case(data: MapData) -> Dictionary:
	for cover: MapCellData in data.cells.values():
		if cover.cover_type != MapCellData.CoverType.LOW: continue
		for direction in [Vector3i.RIGHT, Vector3i.BACK]:
			var attacker := data.get_cell(cover.grid_position - direction)
			var target := data.get_cell(cover.grid_position + direction)
			if attacker and target and attacker.walkable and attacker.can_stop and target.walkable and target.can_stop:
				return {"attacker": attacker.grid_position, "target": target.grid_position}
	return {}

func _first_clear_pair(data: MapData, grid: GridManager) -> Dictionary:
	var ordered: Array[Vector3i] = []
	for cell: MapCellData in data.cells.values(): ordered.append(cell.grid_position)
	ordered.sort_custom(func(a, b): return a.z < b.z or (a.z == b.z and a.x < b.x))
	for first in ordered:
		var first_data := data.get_cell(first)
		if not first_data.walkable or not first_data.can_stop or grid.is_cell_occupied(first): continue
		for direction in [Vector3i.RIGHT, Vector3i.BACK]:
			var second := data.get_cell(first + direction)
			if second and second.walkable and second.can_stop and second.cover_type == MapCellData.CoverType.NONE and not grid.is_cell_occupied(second.grid_position):
				return {"first": first, "second": second.grid_position}
	return {}

func _legal_terminal_approach(grid: GridManager, terminal: Vector3i) -> Vector3i:
	for offset in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK, Vector3i(-1, 0, -1), Vector3i(1, 0, -1), Vector3i(-1, 0, 1), Vector3i(1, 0, 1)]:
		var candidate: Vector3i = terminal + offset
		var cell := grid.get_cell_data(candidate)
		if cell and cell.walkable and cell.can_stop and CombatRules.can_reach_adjacent(candidate, terminal, grid): return candidate
	return Vector3i(-1, -1, -1)

func _relocate(grid: GridManager, unit: TacticalUnit, destination: Vector3i) -> void:
	var previous := grid.get_unit_grid(unit)
	var occupant := grid.get_unit_at(destination)
	if occupant and occupant != unit: return
	unit.global_position = grid.grid_to_world(destination) + Vector3.UP * unit.standing_height
	grid.update_unit_position(unit, previous, destination)

func check(condition: bool, message: String) -> void:
	if condition: print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)
