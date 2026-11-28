extends SceneTree
## Environmental interaction section of the Tactical Test Range (content integration of the 06.09 door): two independently operable doors, a static window, ways round the building, Guard exposure positions,
## room to test occupancy and leaf obstruction. Run through a real battle on the range; the Interaction Range stays the isolated regression environment (dynamic_door_test).
const Catalog := preload("res://systems/generation/battlefield_catalog.gd")
const LEVEL := "res://levels/prototype_map/prototype_map.tscn"
const NORTH := &"door_north"
const SOUTH := &"door_south"
var checks := 0
var failures := 0
var level: BattleLevel
var grid: GridManager
var battle: BattleController
var service: TacticalActionService
var map: MapData
var player: TacticalUnit
var enemy: TacticalUnit


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func _place(unit: TacticalUnit, cell: Vector3i) -> void:
	grid.update_unit_position(unit, grid.get_unit_grid(unit), cell)
	unit.global_position = grid.grid_to_world(cell) + Vector3.UP * unit.standing_height


func _park() -> void:
	_place(enemy, Vector3i(1, 0, 2))
	_place(player, Vector3i(3, 0, 2))


func _door(id: StringName) -> DoorData:
	return map.doors[id]


func _request(kind: StringName, door_id: StringName, actor: TacticalUnit = null) -> TacticalActionRequest:
	return service.make_door_request(kind, actor if actor != null else player, door_id, TacticalActionRequest.Source.PLAYER)


## Every cell outside `region` (and the cells around it) as a fingerprint, plus the movement parts and shot obstacles that do not belong to the door.
func _fingerprint_excluding(door_id: StringName) -> Dictionary:
	var door := _door(door_id)
	var skip := {}
	for position: Vector3i in door.region():
		skip[position] = true
	var cells := {}
	for position: Vector3i in map.cells.keys():
		if not skip.has(position):
			cells[position] = MapDoors.snapshot(map.cells[position])
	var own_parts: Array = []
	for states in door.movement_parts.values():
		own_parts.append_array(states)
	var parts: Array = []
	for part: AABB in map.movement_parts:
		if not own_parts.has(part):
			parts.append(part)
	parts.sort_custom(func(a, b): return str(a) < str(b))
	var obstacles: Array = []
	for o: MapCellData in map.shot_obstacles:
		if o.door_id != door_id:
			obstacles.append([o.authored_shot_bounds, o.shot_obstacle_label, o.door_id])
	obstacles.sort_custom(func(a, b): return str(a) < str(b))
	return {"cells": cells, "parts": parts, "obstacles": obstacles}


func _length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


func _evaluate(from: Vector3i, to: Vector3i) -> CombatRules.AttackEvaluation:
	_place(player, from)
	_place(enemy, to)
	var e := CombatRules.evaluate_attack(player, enemy, grid, level.get_world_3d())
	_park()
	return e


func _run() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(Catalog.TACTICAL_TEST_RANGE)
	config.player_count = 1
	config.enemy_count = 1
	config.battle_seed = 5
	config.content_manifest = {"population_enabled": false}
	level = load(LEVEL).instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	await create_timer(0.4).timeout
	check(level.battle_initialization_succeeded, "The Tactical Test Range starts a battle with the section")
	battle = level.battle_controller
	grid = battle.grid_manager
	service = battle.action_service
	map = grid.map_data
	player = level.turn_manager.player_units[0]
	enemy = level.turn_manager.enemy_units[0]
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	for node in level.find_children("*AI", "AIController", true, false):
		node.queue_free()
	_park()
	await _content()
	await _independence()
	await _gameplay()
	await _window_and_routes()
	await _guard()
	level.queue_free()
	await process_frame
	print("door_test_section_test: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _content() -> void:
	check(map.generation_errors.is_empty(), "The range compiles without errors (%s)" % [map.generation_errors])
	check(map.doors.size() == 2 and map.doors.has(NORTH) and map.doors.has(SOUTH), "The range has two doors with their own ids (%s)" % [map.doors.keys()])
	var north := _door(NORTH)
	var south := _door(SOUTH)
	check(north.is_captured() and south.is_captured() and north.state == DoorData.CLOSED and south.state == DoorData.CLOSED, "Both doors are captured and start closed")
	var overlap := false
	for position in north.region():
		if south.region().has(position):
			overlap = true
	check(not overlap and north.cell != south.cell, "The two doors' affected regions do not overlap (%s | %s)" % [north.region(), south.region()])
	check(north.cell == Vector3i(11, 0, 17) and south.cell == Vector3i(11, 0, 21), "Each door sits in its own doorway cell")
	check(map.get_cell(Vector3i(11, 0, 18)).walkable and map.get_cell(Vector3i(11, 0, 19)).can_stop, "The building interior is open floor")
	# Existing stations are still where they were.
	for station in [Vector3i(6, 0, 13), Vector3i(11, 0, 13), Vector3i(11, 0, 15), Vector3i(17, 0, 17), Vector3i(19, 0, 19), Vector3i(14, 0, 28)]:
		check(map.get_cell(station) != null, "Existing station cell %s is still present" % station)


func _independence() -> void:
	# Operating one door never alters the other door's state, region geometry, parts or obstacles, nor anything else on the map.
	_park()
	for pair in [[NORTH, SOUTH, Vector3i(11, 0, 16)], [SOUTH, NORTH, Vector3i(11, 0, 22)]]:
		var operated: StringName = pair[0]
		var other: StringName = pair[1]
		var other_state := _door(other).state
		var other_region_before := {}
		for position: Vector3i in _door(other).region():
			other_region_before[position] = MapDoors.snapshot(map.cells[position])
		var rest_before := _fingerprint_excluding(operated)
		var signature_before := SurfaceNavigation.signature(map)
		_place(player, pair[2])
		var opened := await service.submit_door(_request(&"open_door", operated), true)
		check(opened != null, "%s opens (%s)" % [operated, "" if opened != null else service.last_rejection.message])
		check(_door(operated).state == DoorData.OPEN and _door(other).state == other_state, "Opening %s leaves %s %s" % [operated, other, other_state])
		var other_region_after := {}
		for position: Vector3i in _door(other).region():
			other_region_after[position] = MapDoors.snapshot(map.cells[position])
		check(other_region_after == other_region_before, "Opening %s leaves %s's cells exactly as they were" % [operated, other])
		var rest_after := _fingerprint_excluding(operated)
		check(rest_after == rest_before, "Opening %s changes nothing outside its own region, parts and obstacles" % operated)
		check(SurfaceNavigation.signature(map) != signature_before, "...and the geometry signature did change")
		var closed := await service.submit_door(_request(&"close_door", operated), true)
		check(closed != null and _door(operated).state == DoorData.CLOSED, "%s closes again" % operated)
		check(SurfaceNavigation.signature(map) == signature_before, "Closing %s restores the original geometry signature exactly" % operated)
	# Both open at once, then each closed in turn: the other keeps its state.
	_place(player, Vector3i(11, 0, 16))
	await service.submit_door(_request(&"open_door", NORTH), true)
	_place(player, Vector3i(11, 0, 22))
	await service.submit_door(_request(&"open_door", SOUTH), true)
	check(_door(NORTH).state == DoorData.OPEN and _door(SOUTH).state == DoorData.OPEN, "Both doors can be open at the same time")
	_place(player, Vector3i(11, 0, 16))
	await service.submit_door(_request(&"close_door", NORTH), true)
	check(_door(NORTH).state == DoorData.CLOSED and _door(SOUTH).state == DoorData.OPEN, "Closing the north door leaves the south door open")
	_place(player, Vector3i(11, 0, 22))
	await service.submit_door(_request(&"close_door", SOUTH), true)
	check(_door(SOUTH).state == DoorData.CLOSED, "...and the south door then closes")
	# A door is also checked against the other's current geometry: an open north leaf does not make the south door refuse for the wrong reason.
	var ap := player.stats.current_ap
	_place(player, Vector3i(11, 0, 16))
	var revision := service.state_revision
	await service.submit_door(_request(&"open_door", NORTH), true)
	check(service.state_revision == revision + 1 and player.stats.current_ap == ap, "A door change advances the revision once and costs no AP")
	await service.submit_door(_request(&"close_door", NORTH), true)
	_park()


func _gameplay() -> void:
	# Through the ordinary controller entry points (the same ones the HUD button uses).
	_place(player, Vector3i(11, 0, 16))
	check(battle.adjacent_door(player) != null and battle.adjacent_door(player).door_id == NORTH, "At (11,16) the controller offers the north door")
	_place(player, Vector3i(11, 0, 22))
	check(battle.adjacent_door(player) != null and battle.adjacent_door(player).door_id == SOUTH, "At (11,22) it offers the south door")
	_place(player, Vector3i(11, 0, 19))
	check(battle.adjacent_door(player) == null, "In the middle of the room no door is adjacent")
	_place(player, Vector3i(11, 0, 22))
	check(await battle.try_door(player, SOUTH, DoorData.OPEN), "The controller opens the south door")
	check(_door(SOUTH).state == DoorData.OPEN, "...and the committed state is open")
	# Doorway occupancy: a unit standing in the open doorway refuses the close.
	_place(enemy, Vector3i(11, 0, 21))
	var occupied := service.query_door(&"close_door", player.tactical_id, SOUTH)
	check(not occupied.is_legal() and occupied.validation.code == &"door_occupied", "A unit in the doorway refuses the close (%s)" % occupied.validation.code)
	_place(enemy, Vector3i(1, 0, 2))
	check(await battle.try_door(player, SOUTH, DoorData.CLOSED), "...and with the doorway clear it closes")
	# Leaf obstruction. The north leaf swings outward (north): a unit at (12,16) is in the way; the south leaf swings inward: a unit at (12,20) is in the way.
	_place(player, Vector3i(11, 0, 16))
	_place(enemy, Vector3i(12, 0, 16))
	var blocked_out := service.query_door(&"open_door", player.tactical_id, NORTH)
	check(not blocked_out.is_legal() and blocked_out.validation.code == &"leaf_obstructed", "A unit beside the doorway where the north leaf swings out refuses the opening (%s)" % blocked_out.validation.code)
	_place(player, Vector3i(11, 0, 22))
	_place(enemy, Vector3i(12, 0, 20))
	var blocked_in := service.query_door(&"open_door", player.tactical_id, SOUTH)
	check(not blocked_in.is_legal() and blocked_in.validation.code == &"leaf_obstructed", "A unit inside where the south leaf swings in refuses the opening (%s)" % blocked_in.validation.code)
	_place(enemy, Vector3i(10, 0, 19))
	check(service.query_door(&"open_door", player.tactical_id, SOUTH).is_legal(), "Elsewhere in the room the same door opens (the room has space for both cases)")
	# From inside the building the north door is reachable too (the free action needs no particular side).
	_place(player, Vector3i(11, 0, 18))
	check(service.query_door(&"open_door", player.tactical_id, NORTH).is_legal(), "From inside, the north door can be opened")
	_park()


func _window_and_routes() -> void:
	# The window is a static aperture: it never changes with either door, and a shot through it behaves the same with every door state.
	var window_cell := map.get_cell(Vector3i(13, 0, 19))
	check(window_cell != null and window_cell.door_id == &"", "The window cell belongs to no door")
	var through_window := _evaluate(Vector3i(15, 0, 19), Vector3i(11, 0, 19))
	check(through_window.is_legal, "A shot from outside the east window to the room is legal (%s)" % [through_window.blocking_cell.shot_obstacle_label if through_window.blocking_cell != null else "clear"])
	var off_axis := _evaluate(Vector3i(15, 0, 20), Vector3i(11, 0, 19))
	var wall_shot := _evaluate(Vector3i(15, 0, 17), Vector3i(11, 0, 18))
	check(not wall_shot.is_legal, "A shot into the room through the plain east wall is blocked")
	var before := [through_window.is_legal, through_window.hit_chance, through_window.cover_type, off_axis.is_legal, off_axis.hit_chance]
	_place(player, Vector3i(11, 0, 16))
	await service.submit_door(_request(&"open_door", NORTH), true)
	_place(player, Vector3i(11, 0, 22))
	await service.submit_door(_request(&"open_door", SOUTH), true)
	var w2 := _evaluate(Vector3i(15, 0, 19), Vector3i(11, 0, 19))
	var o2 := _evaluate(Vector3i(15, 0, 20), Vector3i(11, 0, 19))
	check([w2.is_legal, w2.hit_chance, w2.cover_type, o2.is_legal, o2.hit_chance] == before, "The window's shot results are identical with both doors open")
	# Through-the-door shots follow the door state.
	_place(player, Vector3i(11, 0, 22))
	await service.submit_door(_request(&"close_door", SOUTH), true)
	_place(player, Vector3i(11, 0, 16))
	await service.submit_door(_request(&"close_door", NORTH), true)
	var closed_shot := _evaluate(Vector3i(11, 0, 15), Vector3i(11, 0, 19))
	check(not closed_shot.is_legal and closed_shot.blocking_cell != null and closed_shot.blocking_cell.shot_obstacle_label == "Closed door", "With the north door closed, a shot through it is blocked by the door")
	_place(player, Vector3i(11, 0, 16))
	await service.submit_door(_request(&"open_door", NORTH), true)
	var open_shot := _evaluate(Vector3i(11, 0, 15), Vector3i(11, 0, 19))
	check(open_shot.is_legal, "...and legal once it is open")
	await service.submit_door(_request(&"close_door", NORTH), true)
	# Routes: with both doors closed the building can be walked around; opening a door adds a shorter way through.
	_park()
	var around := battle.pathfinder.calculate_path_with_occupancy(Vector3i(11, 0, 15), Vector3i(11, 0, 23), grid, player)
	var around_length := _length(around)
	var through_cells := false
	for point in around:
		var cell := grid.world_to_grid(point)
		if cell.x >= 10 and cell.x <= 12 and cell.z >= 18 and cell.z <= 20:
			through_cells = true
	check(around.size() > 0 and not through_cells, "With both doors closed there is a route around the building and none through it (%.1f m)" % around_length)
	_place(player, Vector3i(11, 0, 16))
	await service.submit_door(_request(&"open_door", NORTH), true)
	_place(player, Vector3i(11, 0, 22))
	await service.submit_door(_request(&"open_door", SOUTH), true)
	_park()
	var through := battle.pathfinder.calculate_path_with_occupancy(Vector3i(11, 0, 15), Vector3i(11, 0, 23), grid, player)
	var uses_room := false
	for point in through:
		var cell := grid.world_to_grid(point)
		if cell.x >= 10 and cell.x <= 12 and cell.z >= 18 and cell.z <= 20:
			uses_room = true
	check(through.size() > 0 and uses_room and _length(through) < around_length, "With both doors open the straight way through the room is shorter (%.1f m vs %.1f m)" % [_length(through), around_length])
	_place(player, Vector3i(11, 0, 22))
	await service.submit_door(_request(&"close_door", SOUTH), true)
	_place(player, Vector3i(11, 0, 16))
	await service.submit_door(_request(&"close_door", NORTH), true)
	# Deployment to the section: a deployment cell reaches the doors' approach cells by ground.
	for target in [Vector3i(11, 0, 16), Vector3i(11, 0, 22)]:
		var walk := battle.pathfinder.calculate_path_with_occupancy(Vector3i(2, 0, 16), target, grid, player)
		check(walk.size() > 0, "A deployment cell reaches %s on foot" % target)
	_park()


func _arm(watcher: TacticalUnit) -> void:
	watcher.tactical_state.is_overwatching = true


func _guard() -> void:
	# Guard exposure when opening: a watcher inside the room, in line with the north door, gets a newly legal shot at whoever opens it.
	_park()
	_place(enemy, Vector3i(11, 0, 19))
	_arm(enemy)
	_place(player, Vector3i(11, 0, 16))
	var before_ap := player.stats.current_ap
	var result := await service.submit_door(_request(&"open_door", NORTH), true)
	check(result != null and result.reaction_events.size() == 1 and result.reaction_events[0].watcher_id == enemy.tactical_id, "A watcher inside, in line with the north door, reacts when it is opened")
	check(player.stats.current_ap == before_ap and _door(NORTH).state == DoorData.OPEN and _door(SOUTH).state == DoorData.CLOSED, "The opener's AP is untouched, the door is open and the other door is unaffected")
	# The same watcher is blocked from the south approach while the south door is closed, and gets a reaction when it opens.
	var close := await service.submit_door(_request(&"close_door", NORTH), true)
	check(close != null and close.reaction_events.is_empty(), "Closing provokes nothing")
	player.stats.is_defeated = false
	player.stats.current_hp = player.stats.max_hp
	_arm(enemy)
	_place(enemy, Vector3i(11, 0, 19))
	_place(player, Vector3i(11, 0, 22))
	var south := await service.submit_door(_request(&"open_door", SOUTH), true)
	check(south != null and south.reaction_events.size() == 1, "The south door gives the same exposure from the other side")
	check(_door(NORTH).state == DoorData.CLOSED, "...without touching the north door")
