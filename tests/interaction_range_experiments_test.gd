extends SceneTree
## Milestone 06.08 research: how the existing game reads the Interaction Range's STATIC door states, through real battles (the real compiler, standing-point resolver, movement graph and shot rules). Nothing here
## is dynamic: the two door states are two compiled maps (seed parity: even closed, odd open). Each experiment states the question, the measurement and the control that shows the measurement can fail.
##   godot_console --headless --path . --script res://tests/interaction_range_experiments_test.gd
## Prints an EXPERIMENT line per measurement (the report copies them) and checks the findings that must stay true while the map exists.
const Catalog := preload("res://systems/generation/battlefield_catalog.gd")
const LEVEL := "res://levels/prototype_map/prototype_map.tscn"
var checks := 0
var failures := 0
var level: BattleLevel
var grid: GridManager
var battle: BattleController
var player: TacticalUnit
var enemy: TacticalUnit


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func note(text: String) -> void:
	print("EXPERIMENT ", text)


func _open_battle(map_seed: int) -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(Catalog.INTERACTION_RANGE)
	config.player_count = 1
	config.enemy_count = 1
	config.battle_seed = map_seed
	level = load(LEVEL).instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	await create_timer(0.3).timeout
	battle = level.battle_controller
	grid = battle.grid_manager
	player = level.turn_manager.player_units[0]
	enemy = level.turn_manager.enemy_units[0]
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF


func _close_battle() -> void:
	level.queue_free()
	await process_frame
	await process_frame


func _place(unit: TacticalUnit, cell: Vector3i) -> void:
	grid.update_unit_position(unit, grid.get_unit_grid(unit), cell)
	unit.global_position = grid.grid_to_world(cell) + Vector3.UP * unit.standing_height


func _park(unit: TacticalUnit) -> void:
	_place(unit, Vector3i(0, 0, 0))


## Path cost and length for `unit` from its cell to `target` over the live movement graph (occupancy respected).
func _route(unit: TacticalUnit, target: Vector3i) -> Dictionary:
	var path := battle.pathfinder.calculate_path_with_occupancy(grid.get_unit_grid(unit), target, grid, unit)
	var through_door := false
	for point in path:
		var cell := grid.world_to_grid(point)
		if cell == Vector3i(7, 0, 12):
			through_door = true
	return {"exists": path.size() > 0, "points": path.size(), "length": _path_length(path), "through_door_cell": through_door}


func _path_length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


func _evaluate(from_cell: Vector3i, to_cell: Vector3i) -> CombatRules.AttackEvaluation:
	_place(player, from_cell)
	_place(enemy, to_cell)
	return CombatRules.evaluate_attack(player, enemy, grid, level.get_world_3d())


func _describe(e: CombatRules.AttackEvaluation) -> String:
	return "legal %s, hit %d%%, cover %s, exposure %s, blocker %s" % [e.is_legal, e.hit_chance, e.cover_type, e.obstruction_label if "obstruction_label" in e else e.reason, e.blocking_cell.shot_obstacle_label if e.blocking_cell != null and e.blocking_cell.shot_obstacle_label != "" else (str(e.blocking_cell.grid_position) if e.blocking_cell != null else "none")]


func _run() -> void:
	for map_seed in [2, 3]:
		var state := "CLOSED" if map_seed % 2 == 0 else "OPEN"
		await _open_battle(map_seed)
		check(battle.initialization_succeeded if "initialization_succeeded" in battle else level.battle_initialization_succeeded, "The Interaction Range builds a real battle (seed %d, door %s)" % [map_seed, state])
		_structure(state)
		_movement(state)
		_sight(state)
		_cover(state)
		_occupancy(state)
		_guard(state)
		await _close_battle()
	await _match_setup()
	await _mesh_bounds_trap()
	_signatures()
	await _ai_matches()
	print("interaction_range_experiments_test: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures > 0 else 0)


# ------------------------------------------------------------------------------------------------ structure

func _structure(state: String) -> void:
	var data := grid.map_data
	var door := data.get_cell(Vector3i(7, 0, 12))
	var window := data.get_cell(Vector3i(10, 0, 12))
	var doorway := data.get_cell(Vector3i(12, 0, 7))
	var wall := data.get_cell(Vector3i(4, 0, 12))
	note("[%s] cell flags: door cell walkable=%s can_stop=%s; window cell walkable=%s can_stop=%s; exterior doorway walkable=%s can_stop=%s; partition wall walkable=%s" % [state, door.walkable, door.can_stop, window.walkable, window.can_stop, doorway.walkable, doorway.can_stop, wall.walkable])
	check(not wall.walkable and not window.walkable, "[%s] A wall cell and the window cell (a full-height sill) are not walkable" % state)
	check(doorway.walkable and doorway.can_stop, "[%s] The exterior doorway (no leaf) is a free, standable cell: an opening in a wall survives geometry compilation" % state)
	if state == "CLOSED":
		check(not door.walkable and not door.can_stop, "[CLOSED] The closed leaf fills the doorway cell")
	else:
		check(door.walkable and door.can_stop, "[OPEN] With the leaf swung back the doorway cell is free and standable")
	note("[%s] standing-point resolver: door cell standing point offset from its centre = %.3f m" % [state, Vector2(door.world_position.x - door.support_center.x, door.world_position.z - door.support_center.z).length()])


# ------------------------------------------------------------------------------------------------ movement

func _movement(state: String) -> void:
	_park(enemy)
	_place(player, Vector3i(7, 0, 11))
	var through := _route(player, Vector3i(7, 0, 13))
	note("[%s] route (7,11) -> (7,13), the two cells either side of the door: exists %s, %d points, length %.2f m, through the door cell: %s" % [state, through.exists, through.points, through.length, through.through_door_cell])
	var around := _route(player, Vector3i(7, 0, 24))
	note("[%s] route (7,11) -> (7,24) (outside, south of the building): exists %s, length %.2f m, through the door cell: %s" % [state, around.exists, around.length, around.through_door_cell])
	if state == "CLOSED":
		check(through.exists and not through.through_door_cell and through.length > 8.0, "[CLOSED] The planner routes round through the exterior doorways (%.1f m) instead of through the closed door" % through.length)
	else:
		check(through.exists and through.through_door_cell and through.length < 3.0, "[OPEN] The planner steps straight through the open door (%.1f m)" % through.length)
	# Window: never a route, either state (control: the cell is not walkable).
	_place(player, Vector3i(10, 0, 11))
	var window := _route(player, Vector3i(10, 0, 13))
	note("[%s] route (10,11) -> (10,13) across the window: length %.2f m (a route round exists, none through the sill)" % [state, window.length])
	check(window.exists and window.length > 6.0, "[%s] There is no route through the window opening, only round (%.1f m)" % [state, window.length])
	# Diagonal through the doorway: cells (6,12) and (8,12) are wall, so the diagonal (6,11) -> (7,12) and (8,11) -> (7,12) must be refused even when the door is open.
	var diagonal_blocked := not CombatRules.can_reach_adjacent(Vector3i(6, 0, 11), Vector3i(7, 0, 12), grid)
	var straight_ok := CombatRules.can_reach_adjacent(Vector3i(7, 0, 11), Vector3i(7, 0, 12), grid) if state == "OPEN" else true
	note("[%s] diagonal step (6,11) -> (7,12) into the doorway refused by can_reach_adjacent: %s; straight step (7,11) -> (7,12) allowed: %s" % [state, diagonal_blocked, straight_ok if state == "OPEN" else "n/a (door cell closed)"])
	check(diagonal_blocked, "[%s] A diagonal step into the doorway past the jamb is refused (corner blocking)" % state)
	check(straight_ok, "[%s] The straight step into the open doorway is allowed" % state)


# ------------------------------------------------------------------------------------------------ line of sight

func _sight(state: String) -> void:
	_park(enemy)
	var through_door := _evaluate(Vector3i(7, 0, 10), Vector3i(7, 0, 14))
	note("[%s] shot (7,10) -> (7,14) through the door column: %s" % [state, _describe(through_door)])
	var through_wall := _evaluate(Vector3i(4, 0, 10), Vector3i(4, 0, 14))
	note("[%s] shot (4,10) -> (4,14) through the solid partition (control): %s" % [state, _describe(through_wall)])
	var through_window := _evaluate(Vector3i(10, 0, 10), Vector3i(10, 0, 14))
	note("[%s] shot (10,10) -> (10,14) through the window opening: %s" % [state, _describe(through_window)])
	check(not through_wall.is_legal, "[%s] Control: a shot through the solid partition is blocked" % state)
	if state == "CLOSED":
		check(not through_door.is_legal, "[CLOSED] The closed door blocks the shot")
	else:
		check(through_door.is_legal, "[OPEN] The open doorway lets the shot through")
	# The window: the sill is 1.25 m, the standing body is 1.8 m: what do the five body samples see through the opening?
	note("[%s] window shot: sill 1.25 m, head 2.3 m, standing_height of the units %.2f m; visible samples decide legality (see the line above)" % [state, player.standing_height])
	# Rays at fixed heights through the window column, from the exact shot origin line, to show the aperture itself.
	var origin_xz := grid.get_cell_data(Vector3i(10, 0, 10)).world_position
	var dest_xz := grid.get_cell_data(Vector3i(10, 0, 14)).world_position
	var rows := []
	for height in [0.5, 1.0, 1.2, 1.3, 1.8, 2.2, 2.4]:
		var blocker := CombatRules.get_blocking_cell(Vector3(origin_xz.x, height, origin_xz.z), Vector3(dest_xz.x, height, dest_xz.z), grid)
		rows.append("y=%.1f:%s" % [height, "blocked" if blocker != null else "clear"])
	note("[%s] bare rays through the window column at heights: %s" % [state, ", ".join(rows)])
	var door_rows := []
	var door_origin := grid.get_cell_data(Vector3i(7, 0, 10)).world_position
	var door_dest := grid.get_cell_data(Vector3i(7, 0, 14)).world_position
	for height in [0.5, 1.0, 1.8, 2.3, 2.5]:
		var blocker := CombatRules.get_blocking_cell(Vector3(door_origin.x, height, door_origin.z), Vector3(door_dest.x, height, door_dest.z), grid)
		door_rows.append("y=%.1f:%s" % [height, "blocked" if blocker != null else "clear"])
	note("[%s] bare rays through the door column at heights (the lintel starts at 2.4 m): %s" % [state, ", ".join(door_rows)])
	check(("y=1.8:clear" in ", ".join(rows)) and ("y=1.0:blocked" in ", ".join(rows)), "[%s] The window aperture is real: clear between the sill and the head, blocked below the sill" % state)
	check(through_window.is_legal and through_window.hit_chance == 50, "[%s] A shot through the window is legal and exposure-limited to one sample (%d%%): a window is a partial opening, unlike a door" % [state, through_window.hit_chance])


# ------------------------------------------------------------------------------------------------ cover near the doorway edge

func _cover(state: String) -> void:
	_park(enemy)
	# Target stands beside the door jamb in room B ((6,13) is diagonal to the doorway, behind the wall seen from the north-west).
	var beside_jamb := _evaluate(Vector3i(7, 0, 10), Vector3i(6, 0, 13))
	note("[%s] shooter (7,10) at a target beside the jamb (6,13), not in the door column: %s" % [state, _describe(beside_jamb)])
	var in_column := _evaluate(Vector3i(7, 0, 10), Vector3i(7, 0, 13))
	note("[%s] shooter (7,10) at a target in the door column (7,13): %s" % [state, _describe(in_column)])
	var oblique := _evaluate(Vector3i(5, 0, 10), Vector3i(8, 0, 13))
	note("[%s] oblique shooter (5,10) at a target (8,13) through the doorway at an angle: %s" % [state, _describe(oblique)])
	if state == "OPEN":
		check(in_column.is_legal and in_column.hit_chance == 100 and beside_jamb.is_legal and beside_jamb.hit_chance < in_column.hit_chance and beside_jamb.cover_type == MapCellData.CoverType.FULL, "[OPEN] In the door column the target is fully exposed (%d%%); one cell aside the jamb is full cover and the shot falls to %d%%" % [in_column.hit_chance, beside_jamb.hit_chance])
		# 06.09: the open leaf is now the real door leaf at its settled 100 degree pose, flush against the north wall beside the doorway, so the 06.08 oblique line no longer meets it (leaf blocking is asserted in dynamic_door_test along the leaf).
		check(oblique.is_legal and oblique.blocking_cell != null and oblique.blocking_cell.shot_obstacle_label != "Open door leaf", "[OPEN] The settled leaf lies beside the doorway, so the oblique line through the doorway is legal and the leaf is not what shapes it (06.09 pose; 06.08 used a cruder box)")
	else:
		check(not in_column.is_legal and not beside_jamb.is_legal, "[CLOSED] Neither is exposed with the door closed")
	# The sample count behind the window: the units are 1.0 m tall here, the sill is 1.25 m, so only the highest body sample clears it.


# ------------------------------------------------------------------------------------------------ occupancy

func _occupancy(state: String) -> void:
	_park(enemy)
	if state != "OPEN":
		return
	var door_cell := Vector3i(7, 0, 12)
	_place(enemy, door_cell)
	_place(player, Vector3i(7, 0, 11))
	var blocked := _route(player, Vector3i(7, 0, 13))
	note("[OPEN] a unit standing in the doorway: route (7,11) -> (7,13) length %.2f m, through the door cell: %s (an occupied doorway blocks the way as any occupied cell does; the planner goes round)" % [blocked.length, blocked.through_door_cell])
	check(not blocked.through_door_cell and blocked.length > 8.0, "[OPEN] A unit in the doorway forces the route round: occupancy already blocks a door cell")
	_park(enemy)


# ------------------------------------------------------------------------------------------------ guard

## Guard (overwatch) reads the same shot rules at a checkpoint cell. A watcher covering the doorway from room A: can it fire at a hostile standing in the door column, and in the cell beside the jamb?
func _guard(state: String) -> void:
	_park(enemy)
	_place(player, Vector3i(7, 0, 9))
	player.tactical_state.is_overwatching = true
	var rows := []
	for cell in [Vector3i(7, 0, 12), Vector3i(7, 0, 13), Vector3i(6, 0, 13), Vector3i(7, 0, 15)]:
		if grid.get_cell_data(cell) == null or not grid.get_cell_data(cell).can_stop and cell != Vector3i(7, 0, 12):
			continue
		_place(enemy, cell)
		var reaction := battle.action_service.query_guard_reaction(player, enemy, cell)
		rows.append("%s:%s" % [cell, "fire" if reaction.can_fire else "no (%s)" % reaction.reason])
	note("[%s] Guard from (7,9): hostile at %s" % [state, ", ".join(rows)])
	player.tactical_state.is_overwatching = false
	_park(enemy)
	if state == "OPEN":
		check("(7, 0, 13):fire" in ", ".join(rows), "[OPEN] A Guard watcher can fire at a hostile in the door column beyond the open door")
	else:
		check("(7, 0, 13):fire" not in ", ".join(rows), "[CLOSED] The same Guard watcher cannot fire through the closed door")


# ------------------------------------------------------------------------------------------------ the mesh-bounds trap

func _mesh_bounds_trap() -> void:
	const Bake := preload("res://tools/parcel_editor/mesh_tactical_bounds.gd")
	const KIT := "res://art/environments/kenney/factory_kit/models/"
	for model in ["structure-wall", "structure-doorway", "structure-window"]:
		var holder := Node3D.new()
		var instance := (load(KIT + model + ".glb") as PackedScene).instantiate() as Node3D
		instance.scale = Vector3(1.5, 1.5, 1.5)
		holder.add_child(instance)
		var count := Bake.add_to(holder)
		var sizes := []
		for part in holder.find_children("*", "Node3D", true, false):
			if part.has_meta("solid_size"):
				sizes.append(part.get_meta("solid_size"))
		note("kit piece '%s' through the editor's mesh bake (scale 1.5): %d part(s), solid_size %s (the real wall is 0.3 m thick)" % [model, count, sizes])
		var world_depth: float = (sizes[0] as Vector3).z * 1.5
		note("  world depth of the baked box: %.2f m (the wall plane is 0.3 m)" % world_depth)
		check(count == 1 and world_depth > 2.5, "'%s': the mesh bake makes one box %.1f m deep, ten times the real wall thickness (%s)" % [model, world_depth, sizes])
		# Compile the baked piece into a map and see whether the doorway survives.
		var data := TacticalMapBuilder.generate(9, 9, 1.0, 1)
		data.surface_placement_enabled = true
		holder.position = data.get_cell(Vector3i(4, 0, 4)).world_position
		AuthoredSceneMapCompiler.compile(holder, data, 1.0)
		SurfaceNavigation.resolve_map(data, 1.0, true)
		var middle := data.get_cell(Vector3i(4, 0, 4))
		var behind := data.get_cell(Vector3i(4, 0, 5))
		note("  compiled: the cell at the piece's origin walkable=%s, the cell behind it walkable=%s" % [middle.walkable, behind.walkable])
		if model == "structure-doorway":
			check(not middle.walkable, "'structure-doorway' baked from its mesh: the doorway opening is NOT preserved (the whole piece is one solid box)")
		holder.free()


# ------------------------------------------------------------------------------------------------ signatures

func _signatures() -> void:
	var closed := Catalog.generate(Catalog.INTERACTION_RANGE, Vector2i.ZERO, 2, 1.0)
	var open := Catalog.generate(Catalog.INTERACTION_RANGE, Vector2i.ZERO, 3, 1.0)
	var closed_signature := SurfaceNavigation.signature(closed)
	var open_signature := SurfaceNavigation.signature(open)
	note("geometry signatures: closed %s... open %s... (equal: %s); los_revision closed %d, open %d" % [closed_signature.substr(0, 12), open_signature.substr(0, 12), closed_signature == open_signature, closed.los_revision, open.los_revision])
	check(closed_signature != open_signature, "The compiled geometry signature differs between the door states, so the replay fingerprint (which includes it) tells them apart")
	check(closed_signature == SurfaceNavigation.signature(Catalog.generate(Catalog.INTERACTION_RANGE, Vector2i.ZERO, 2, 1.0)), "The signature is deterministic for the same seed")


# ------------------------------------------------------------------------------------------------ AI

## Whole AI-vs-AI matches on each door state (the existing simulator): does the AI plan, move and finish on the new map, and how do the two states differ? This is observation, not a balance claim.
func _ai_matches() -> void:
	for map_seed in [2, 3]:
		var simulator := AIMatchSimulator.new()
		root.add_child(simulator)
		var result: AIMatchSimulationResult = await simulator.run_match({"seed": map_seed, "generated_map": true, "battlefield_id": Catalog.INTERACTION_RANGE, "player_count": 2, "enemy_count": 2, "maximum_rounds": 12, "timeout_seconds": 60.0})
		note("[AI door %s] status %s (0 = completed), battle result %s (1 = player victory, 2 = defeat), rounds %d, decisions %d, committed %d, rejected %d (one seed per state: an observation, not a balance claim)" % ["CLOSED" if map_seed % 2 == 0 else "OPEN", result.status, result.battle_result, result.rounds, result.decision_count, result.committed_action_count, result.rejected_action_count])
		check(result.committed_action_count > 0 and result.validation_errors.is_empty(), "[AI door %s] The AI plans and commits actions on the Interaction Range without validation errors (%d actions)" % ["CLOSED" if map_seed % 2 == 0 else "OPEN", result.committed_action_count])
		simulator.queue_free()
		await process_frame


# ------------------------------------------------------------------------------------------------ the game interface

## The map is offered by the real Match Setup screen and builds the configuration a battle starts from.
func _match_setup() -> void:
	var menu: Node = load("res://ui/match_setup.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var found := -1
	for index in menu.map_size_option.item_count:
		if StringName(menu.map_size_option.get_item_metadata(index)) == Catalog.INTERACTION_RANGE:
			found = index
	check(found >= 0, "Match Setup lists the Interaction Range")
	if found >= 0:
		menu.map_size_option.select(found)
		menu._on_battlefield_selected(found)
		var config: BattleConfiguration = menu._build_battle_configuration()
		note("Match Setup entry: label '%s', battlefield %s, map size %s, population toggle pressed %s" % [menu.map_size_option.get_item_text(found), config.battlefield_id, config.map_size, menu.population_toggle.button_pressed])
		check(config.battlefield_id == Catalog.INTERACTION_RANGE and config.map_size == Vector2i(16, 32) and not menu.population_toggle.button_pressed, "Selecting it builds an Interaction Range configuration (16 x 32, no population)")
	menu.queue_free()
	await process_frame
