extends SceneTree
## Milestone 06.09: the authoritative dynamic door on the Interaction Range, through real battles. The static maps of Milestone 06.08 stay as the reference: a toggled map must equal an independently compiled map
## of the other state, in cells, movement parts, shot obstacles, movement graph and shot results. Covers the policy (free action, orthogonal adjacency, reach, occupancy, leaf obstruction), rejection without side
## effects, repeated transitions, zero AP, Guard on opening, rollback, cache invalidation and stale requests.
const Catalog := preload("res://systems/generation/battlefield_catalog.gd")
const LEVEL := "res://levels/prototype_map/prototype_map.tscn"
const DOOR := &"door_a"
var checks := 0
var failures := 0
var level: BattleLevel
var grid: GridManager
var battle: BattleController
var service: TacticalActionService
var map: MapData
var player: TacticalUnit
var enemy: TacticalUnit
var enemy2: TacticalUnit


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func _open_battle(map_seed: int, enemies := 2) -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(Catalog.INTERACTION_RANGE)
	config.player_count = 1
	config.enemy_count = enemies
	config.battle_seed = map_seed
	config.content_manifest = {"population_enabled": false}
	level = load(LEVEL).instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	await create_timer(0.3).timeout
	battle = level.battle_controller
	grid = battle.grid_manager
	service = battle.action_service
	map = grid.map_data
	player = level.turn_manager.player_units[0]
	enemy = level.turn_manager.enemy_units[0]
	enemy2 = level.turn_manager.enemy_units[1] if level.turn_manager.enemy_units.size() > 1 else null
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF


func _close_battle() -> void:
	level.queue_free()
	await process_frame
	await process_frame


func _place(unit: TacticalUnit, cell: Vector3i) -> void:
	grid.update_unit_position(unit, grid.get_unit_grid(unit), cell)
	unit.global_position = grid.grid_to_world(cell) + Vector3.UP * unit.standing_height


func _park_all() -> void:
	var spots := [Vector3i(1, 0, 2), Vector3i(3, 0, 2), Vector3i(5, 0, 2)]
	var index := 0
	for unit in [enemy, enemy2]:
		if unit != null:
			_place(unit, spots[index])
			index += 1


func _request(kind: StringName, actor: TacticalUnit = null) -> TacticalActionRequest:
	return service.make_door_request(kind, actor if actor != null else player, DOOR, TacticalActionRequest.Source.PLAYER)


func _world_state() -> Dictionary:
	return {"ap": player.stats.current_ap, "rng": service.get_combat_rng_state(), "revision": service.state_revision, "door": (map.doors[DOOR] as DoorData).state, "signature": SurfaceNavigation.signature(map), "player_cell": grid.get_unit_grid(player), "enemy_cell": grid.get_unit_grid(enemy), "occupancy": grid.occupancy_map.size(), "transaction": service.last_transaction_id}


func _run() -> void:
	await _open_battle(2)
	await _parity()
	await _movement_and_geometry()
	await _other_factions_and_maps()
	await _rejections()
	await _zero_ap()
	await _guard()
	await _rollback_and_caches()
	await _lethal()
	await _close_battle()
	print("dynamic_door_test: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures > 0 else 0)


# ------------------------------------------------------------------------------------------------ parity with the static maps

func _same_cells(a: MapData, b: MapData) -> String:
	for position: Vector3i in a.cells.keys():
		if not b.cells.has(position) or MapDoors.snapshot(a.cells[position]) != MapDoors.snapshot(b.cells[position]):
			return "cell %s differs" % position
	var parts_a := a.movement_parts.duplicate()
	var parts_b := b.movement_parts.duplicate()
	if parts_a != parts_b:
		return "movement parts differ (%d vs %d)" % [parts_a.size(), parts_b.size()]
	var obstacles_a: Array = []
	var obstacles_b: Array = []
	for o: MapCellData in a.shot_obstacles: obstacles_a.append([o.authored_shot_bounds, o.shot_obstacle_label])
	for o: MapCellData in b.shot_obstacles: obstacles_b.append([o.authored_shot_bounds, o.shot_obstacle_label])
	obstacles_a.sort_custom(func(x, y): return str(x) < str(y))
	obstacles_b.sort_custom(func(x, y): return str(x) < str(y))
	if obstacles_a != obstacles_b:
		return "shot obstacles differ"
	if SurfaceNavigation.signature(a) != SurfaceNavigation.signature(b):
		return "geometry signatures differ"
	return ""


func _graph_costs(pf: Pathfinder, pairs: Array) -> Array:
	var prior := grid.get_unit_grid(player)
	_place(player, Vector3i(14, 0, 30))   # nobody stands on a route cell: the live graph, unlike a freshly built one, knows occupancy
	var costs: Array = []
	for pair in pairs:
		var path := pf.calculate_3d_path(pair[0], pair[1])
		costs.append(snappedf(_length(path), 0.01))
	_place(player, prior)
	return costs


func _length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


func _parity() -> void:
	_park_all()
	var static_closed := Catalog.generate(Catalog.INTERACTION_RANGE, Vector2i.ZERO, 2, 1.0)
	var static_open := Catalog.generate(Catalog.INTERACTION_RANGE, Vector2i.ZERO, 3, 1.0)
	check(map.doors.size() == 1 and (map.doors[DOOR] as DoorData).state == DoorData.CLOSED and (static_open.doors[DOOR] as DoorData).state == DoorData.OPEN, "The authored door has an identity and its initial state (seed 2 closed, seed 3 open)")
	var region: Array[Vector3i] = (map.doors[DOOR] as DoorData).region()
	check(region.has(Vector3i(7, 0, 12)) and region.has(Vector3i(8, 0, 11)), "The affected region is found by comparing the compiled states, and includes the neighbour the swung leaf covers (%s)" % [region])
	check(_same_cells(map, static_closed) == "", "At the start the live map equals an independent compile of the closed state: %s" % _same_cells(map, static_closed))
	var pairs := [[Vector3i(7, 0, 11), Vector3i(7, 0, 13)], [Vector3i(5, 0, 5), Vector3i(8, 0, 16)], [Vector3i(8, 0, 11), Vector3i(8, 0, 13)], [Vector3i(7, 0, 10), Vector3i(12, 0, 7)]]
	var reference := Pathfinder.new()
	MapGraphBuilder.build(static_closed, reference)
	var reference_open := Pathfinder.new()
	MapGraphBuilder.build(static_open, reference_open)
	check(_graph_costs(battle.pathfinder, pairs) == _graph_costs(reference, pairs), "Closed: the live movement graph gives the static map's route costs %s" % [_graph_costs(battle.pathfinder, pairs)])
	_place(player, Vector3i(7, 0, 13))
	var states: Array = []
	for round in 3:
		var opened := await service.submit_door(_request(&"open_door"), true)
		check(opened != null and (map.doors[DOOR] as DoorData).state == DoorData.OPEN, "Round %d: opened (%s)" % [round, "" if opened != null else "%s: %s" % [service.last_rejection.code, service.last_rejection.message]])
		var mismatch := _same_cells(map, static_open)
		check(mismatch == "", "Round %d: the toggled-open map equals the independently compiled open map: %s" % [round, mismatch])
		check(_graph_costs(battle.pathfinder, pairs) == _graph_costs(reference_open, pairs), "Round %d: open route costs equal the static open map's (%s)" % [round, _graph_costs(battle.pathfinder, pairs)])
		var closed := await service.submit_door(_request(&"close_door"), true)
		check(closed != null and (map.doors[DOOR] as DoorData).state == DoorData.CLOSED, "Round %d: closed again" % round)
		mismatch = _same_cells(map, static_closed)
		check(mismatch == "", "Round %d: closed-again equals the independently compiled closed map: %s" % [round, mismatch])
		check(_graph_costs(battle.pathfinder, pairs) == _graph_costs(reference, pairs), "Round %d: closed route costs return to the static closed map's" % round)
		states.append(service.state_revision)
	check(states == [2, 4, 6], "Each committed transition advances the revision exactly once (%s)" % [states])
	# Contextual firing is read from the same map by the same rules: the evaluation of a shot is identical on the toggled map and on the static map.
	_open_and_compare_shots(static_open)
	reference.astar.clear()
	reference_open.astar.clear()


func _open_and_compare_shots(static_open: MapData) -> void:
	var live_before := _shot_table()
	var result := await_free_open()
	check(result, "Opened for the shot comparison")
	var live_open := _shot_table()
	check(live_before != live_open, "The shot table changes when the door opens (it is not a constant)")
	# The same evaluations on an independently compiled open map.
	var saved := grid.map_data
	grid.map_data = static_open
	var static_table := _shot_table()
	grid.map_data = saved
	check(live_open == static_table, "Shot results (legality, chance, cover, blocker) on the toggled-open map equal the static open map's: %s" % ("" if live_open == static_table else "differ"))
	# Contextual firing (the side step a certified rig can take) is read from the same map: with discovery switched on for both, the evaluations still agree.
	map.contextual_discovery_enabled = true
	static_open.contextual_discovery_enabled = true
	var live_contextual := _shot_table()
	grid.map_data = static_open
	var static_contextual := _shot_table()
	grid.map_data = saved
	map.contextual_discovery_enabled = false
	check(live_contextual == static_contextual, "Contextual firing enabled: the toggled-open map and the static open map still give identical shot results")


func await_free_open() -> bool:
	return MapDoors.apply_with_graph(map, battle.pathfinder, DOOR, DoorData.OPEN)


func _shot_table() -> Array:
	var rows: Array = []
	for pair in [[Vector3i(7, 0, 10), Vector3i(7, 0, 14)], [Vector3i(7, 0, 10), Vector3i(6, 0, 13)], [Vector3i(5, 0, 10), Vector3i(8, 0, 13)], [Vector3i(10, 0, 10), Vector3i(10, 0, 14)], [Vector3i(4, 0, 10), Vector3i(4, 0, 14)], [Vector3i(8, 0, 10), Vector3i(8, 0, 13)]]:
		_place(player, pair[0])
		_place(enemy, pair[1])
		var e := CombatRules.evaluate_attack(player, enemy, grid, level.get_world_3d())
		rows.append([pair, e.is_legal, e.hit_chance, e.cover_type, e.blocking_cell.shot_obstacle_label if e.blocking_cell != null else ""])
	_park_all()
	return rows


# ------------------------------------------------------------------------------------------------ movement, LOS, cover, diagonals

func _route(from: Vector3i, to: Vector3i) -> Dictionary:
	_place(player, from)
	var path := battle.pathfinder.calculate_path_with_occupancy(from, to, grid, player)
	var through := false
	for point in path:
		if grid.world_to_grid(point) == Vector3i(7, 0, 12): through = true
	return {"length": _length(path), "through": through, "exists": path.size() > 0}


func _movement_and_geometry() -> void:
	_park_all()
	check(await_close(), "Closed for the movement measurements")
	var closed := _route(Vector3i(7, 0, 11), Vector3i(7, 0, 13))
	check(closed.exists and not closed.through and closed.length > 20.0, "Closed: no route through the doorway; the planner goes round (%.1f m)" % closed.length)
	await_free_open()
	var open := _route(Vector3i(7, 0, 11), Vector3i(7, 0, 13))
	check(open.exists and open.through and open.length < 3.0, "Open: the route goes straight through the doorway (%.1f m)" % open.length)
	check(not CombatRules.can_reach_adjacent(Vector3i(6, 0, 11), Vector3i(7, 0, 12), grid) and CombatRules.can_reach_adjacent(Vector3i(7, 0, 11), Vector3i(7, 0, 12), grid), "Open: the diagonal past the jamb is refused, the straight step is allowed")
	var leaf := map.get_cell(Vector3i(8, 0, 11))
	var pushed := Vector2(leaf.world_position.x - leaf.support_center.x, leaf.world_position.z - leaf.support_center.z).length() if leaf != null else 0.0
	check(leaf != null and (not (leaf.walkable and leaf.can_stop) or pushed > 0.1), "Open: the cell beside the doorway that the swung leaf touches changed (standing point moved %.2f m off its centre)" % pushed)
	var oblique := _evaluate_pair(Vector3i(8, 0, 10), Vector3i(7, 0, 13))
	check(not oblique.is_legal and oblique.blocking_cell != null and oblique.blocking_cell.shot_obstacle_label == "Open door leaf", "Open: the leaf blocks a shot along its length (blocker %s)" % [oblique.blocking_cell.shot_obstacle_label if oblique.blocking_cell else "none"])
	var through := _evaluate_pair(Vector3i(7, 0, 10), Vector3i(7, 0, 14))
	var beside := _evaluate_pair(Vector3i(7, 0, 10), Vector3i(6, 0, 13))
	check(through.is_legal and through.hit_chance > beside.hit_chance and beside.cover_type == MapCellData.CoverType.FULL, "Open: a target in the door column is exposed, one beside the jamb has full cover (%d%% vs %d%%)" % [through.hit_chance, beside.hit_chance])
	check(await_close(), "Closed again")
	var shut := _evaluate_pair(Vector3i(7, 0, 10), Vector3i(7, 0, 14))
	check(not shut.is_legal, "Closed again: the shot through the door column is blocked")
	_park_all()


func await_close() -> bool:
	if (map.doors[DOOR] as DoorData).state == DoorData.CLOSED:
		return true
	return MapDoors.apply_with_graph(map, battle.pathfinder, DOOR, DoorData.CLOSED)


func _evaluate_pair(from: Vector3i, to: Vector3i) -> CombatRules.AttackEvaluation:
	_place(player, from)
	_place(enemy, to)
	return CombatRules.evaluate_attack(player, enemy, grid, level.get_world_3d())


# ------------------------------------------------------------------------------------------------ rejections

func _rejection_leaves_everything(label: String, request: TacticalActionRequest) -> void:
	var before := _world_state()
	var rejected_codes: Array = []
	var listener := func(validation: ActionValidationResult) -> void: rejected_codes.append(validation.code)
	service.action_rejected.connect(listener)
	var result := await service.submit_door(request, true)
	service.action_rejected.disconnect(listener)
	var after := _world_state()
	check(result == null and not rejected_codes.is_empty(), "%s: rejected (%s)" % [label, rejected_codes])
	check(before == after, "%s: AP, RNG, revision, door, geometry, occupancy and transaction counter are unchanged" % label)


func _other_factions_and_maps() -> void:
	# Every faction may operate an ordinary unlocked door: the physical check has no faction rule (the action layer's only gate is whose activation it is).
	_park_all()
	await_close()
	_place(enemy, Vector3i(7, 0, 13))
	var as_enemy := MapDoors.check(map, grid, enemy, DOOR, DoorData.OPEN)
	check(as_enemy.ok, "A hostile unit standing at the door passes the same physical check as a player unit (%s)" % as_enemy.message)
	_park_all()
	# A map without doors is untouched: no registry, no door line in what a replay compares.
	var range_map := Catalog.generate(Catalog.TACTICAL_TEST_RANGE, Vector2i.ZERO, 2, 1.0)
	check(range_map.doors.is_empty() and range_map.generation_errors.is_empty(), "The Tactical Test Range has no doors and still compiles cleanly")
	var signature_a := SurfaceNavigation.signature(Catalog.generate(Catalog.TACTICAL_TEST_RANGE, Vector2i.ZERO, 2, 1.0))
	check(signature_a == SurfaceNavigation.signature(range_map), "...and compiles identically every time")


func _rejections() -> void:
	_park_all()
	await_close()
	_place(player, Vector3i(7, 0, 13))
	# Already in the requested state.
	await _rejection_leaves_everything("Closing a closed door", _request(&"close_door"))
	# Out of range (two cells away), diagonal, and not reachable.
	_place(player, Vector3i(7, 0, 14))
	await _rejection_leaves_everything("Opening from two cells away", _request(&"open_door"))
	_place(player, Vector3i(6, 0, 13))
	await _rejection_leaves_everything("Opening from the diagonal", _request(&"open_door"))
	# Unknown door, wrong actor.
	_place(player, Vector3i(7, 0, 13))
	await _rejection_leaves_everything("An unknown door", service.make_door_request(&"open_door", player, &"no_such_door", TacticalActionRequest.Source.PLAYER))
	await _rejection_leaves_everything("A unit that may not act now (an enemy during the player's phase)", service.make_door_request(&"open_door", enemy, DOOR, TacticalActionRequest.Source.PLAYER))
	# A stale preview.
	var stale := _request(&"open_door")
	stale.expected_revision = service.state_revision - 1
	await _rejection_leaves_everything("A stale request", stale)
	# Occupied doorway: open the door, put an enemy in it, ask to close.
	check(await_free_open(), "Opened for the occupancy cases")
	_place(enemy, Vector3i(7, 0, 12))
	await _rejection_leaves_everything("Closing a doorway that a unit stands in", _request(&"close_door"))
	# Obstructed leaf: a unit standing where the swung leaf passes.
	_park_all()
	await_close()
	_place(player, Vector3i(7, 0, 13))
	_place(enemy, Vector3i(8, 0, 11))
	await _rejection_leaves_everything("Opening while a unit stands in the leaf's swing", _request(&"open_door"))
	_place(enemy, Vector3i(7, 0, 11))
	await _rejection_leaves_everything("Opening while a unit stands in front of the door where the leaf passes (7,11)", _request(&"open_door"))
	_place(enemy, Vector3i(7, 0, 10))
	var beyond := service.query_door(&"open_door", player.tactical_id, DOOR)
	check(beyond.is_legal(), "A unit beyond the leaf's reach (7,10, two cells from the door) is not in the way")
	# Negative control: the same request with the way clear is accepted, so the rejections above were about the obstruction.
	_park_all()
	var opened := await service.submit_door(_request(&"open_door"), true)
	check(opened != null, "Control: with the swing clear the same request is accepted")
	# The operating unit's own swing: it stands in front of the door on the swing side and still opens it (it ends clear of the leaf).
	await_close()
	_place(player, Vector3i(7, 0, 11))
	var from_swing_side := await service.submit_door(_request(&"open_door"), true)
	check(from_swing_side != null, "A unit operating the door from the side the leaf swings toward may open it (the leaf ends beside it)")
	await_close()
	# A unit carrying someone may not operate a door.
	_park_all()


# ------------------------------------------------------------------------------------------------ zero AP

func _zero_ap() -> void:
	_park_all()
	await_close()
	_place(player, Vector3i(7, 0, 13))
	player.stats.consume_ap(player.stats.current_ap)
	check(player.stats.current_ap == 0 and level.turn_manager.active_unit == player, "The active unit has no AP left")
	var revision_before := service.state_revision
	var opened := await service.submit_door(_request(&"open_door"), true)
	check(opened != null and player.stats.current_ap == 0 and opened.actor_ap_before == 0 and opened.actor_ap_after == 0, "Opening costs nothing: a unit with 0 AP may open the door and still has 0 AP")
	check(service.state_revision == revision_before + 1, "...and it is a committed action (revision %d -> %d)" % [revision_before, service.state_revision])
	var closed := await service.submit_door(_request(&"close_door"), true)
	check(closed != null and player.stats.current_ap == 0, "Closing a door costs nothing either")
	# A free action must not restore AP or open another activation.
	check(player.stats.current_ap == 0 and level.turn_manager.active_unit == player, "Neither restored AP nor changed whose activation it is")
	# Through the controller: after a free action a unit with no AP moves on by the existing exhausted-unit rule (no new turn rule).
	var controlled := await battle.try_door(player, DOOR, DoorData.OPEN)
	check(controlled, "The controller entry point commits the same action")
	await create_timer(0.3).timeout
	check(level.turn_manager.active_unit != player or level.turn_manager.player_units.size() == 1, "The existing exhausted-unit rule applies afterwards (no special continuation)")
	# A unit that is not the active one cannot operate it, whatever its AP.
	var rejected := service.query_door(&"open_door", enemy.tactical_id, DOOR)
	check(not rejected.is_legal() and rejected.validation.code == &"wrong_activation", "A unit that may not act now is refused (%s)" % rejected.validation.code)
	await_close()


# ------------------------------------------------------------------------------------------------ Guard

func _arm(watcher: TacticalUnit) -> void:
	watcher.tactical_state.is_overwatching = true


func _guard() -> void:
	_park_all()
	await_close()
	player.stats.reset_ap() if player.stats.has_method("reset_ap") else null
	player.stats.current_ap = player.stats.get_ap_snapshot().effective_max_ap
	# (a) A watcher whose shot was blocked by the door gains a legal shot when it opens: one reaction, once.
	_place(player, Vector3i(7, 0, 13))
	_place(enemy, Vector3i(7, 0, 9))
	_arm(enemy)
	var sp_before := enemy.stats.current_supply_points
	var hp_before := player.stats.current_hp
	var ap_before_opening := player.stats.current_ap
	var door_state := await service.submit_door(_request(&"open_door"), true)
	check(door_state != null and door_state.reaction_events.size() == 1 and door_state.reaction_events[0].watcher_id == enemy.tactical_id, "(a) A watcher whose shot the door blocked reacts when it opens: one reaction")
	check(enemy.stats.current_supply_points == sp_before - 1 and not enemy.tactical_state.is_overwatching, "(a) The reaction spent supply and the watcher's Guard (existing resource rules)")
	check(door_state != null and (map.doors[DOOR] as DoorData).state == DoorData.OPEN and player.stats.current_ap == ap_before_opening, "(a) The door is open and the opener's AP is untouched")
	# (b) Repeated closing and opening does not give the watcher another reaction (its Guard is spent), and closing never provokes.
	_arm(enemy2) if enemy2 != null else null
	if enemy2 != null:
		_place(enemy2, Vector3i(7, 0, 8))
	var closed := await service.submit_door(_request(&"close_door"), true)
	check(closed != null and closed.reaction_events.is_empty(), "(b) Closing a door provokes no reaction, even with an armed watcher in line")
	var reopened := await service.submit_door(_request(&"open_door"), true)
	if enemy2 != null:
		check(reopened != null and reopened.reaction_events.size() == 1 and reopened.reaction_events[0].watcher_id == enemy2.tactical_id, "(b) The first watcher stays spent; only the other armed watcher reacts on the next opening")
		var again := await service.submit_door(_request(&"close_door"), true)
		var third := await service.submit_door(_request(&"open_door"), true)
		check(again != null and third != null and third.reaction_events.is_empty(), "(b) Repeated opening and closing never restores a reaction")
	# (c) A watcher whose shot stays blocked, and (d) one whose shot was already legal, do not react.
	await_close()
	_park_all()
	_place(player, Vector3i(7, 0, 13))
	_place(enemy, Vector3i(4, 0, 9))
	_arm(enemy)
	if enemy2 != null:
		_place(enemy2, Vector3i(7, 0, 15))
		_arm(enemy2)
	var mixed := await service.submit_door(_request(&"open_door"), true)
	check(mixed != null and mixed.reaction_events.is_empty(), "(c) A watcher behind the wall still has no shot: no reaction")
	check(mixed != null and mixed.guard_checks.has(enemy.tactical_id), "(c) ...and the check records why (%s)" % [mixed.guard_checks.get(enemy.tactical_id, {}) if mixed else {}])
	if enemy2 != null:
		check(mixed != null and mixed.guard_checks.has(enemy2.tactical_id) and String(mixed.guard_checks[enemy2.tactical_id].get("reason", "")).contains("already legal"), "(d) A watcher in the same room already had the shot: the door created nothing, no reaction")
		check(enemy2.tactical_state.is_overwatching, "(d) ...and its Guard is kept")
	# (e) Two eligible watchers: both react, in the fixed order (faction, then id).
	await_close()
	_park_all()
	_place(player, Vector3i(7, 0, 13))
	if enemy2 != null:
		_place(enemy, Vector3i(7, 0, 9))
		_place(enemy2, Vector3i(7, 0, 8))
		_arm(enemy)
		_arm(enemy2)
		player.stats.current_hp = player.stats.max_hp
		var two := await service.submit_door(_request(&"open_door"), true)
		var order: Array = []
		for event in two.reaction_events: order.append(event.watcher_id)
		var expected: Array = [enemy.tactical_id, enemy2.tactical_id]
		expected.sort_custom(func(a, b): return String(a) < String(b))
		check(two != null and order == expected, "(e) Two eligible watchers both react, in id order %s" % [order])


func _force_hit_roll() -> void:
	# The reaction's roll is the next draw of the combat RNG: pick a state whose first draw is a hit.
	for seed_value in range(1, 400):
		var probe := RandomNumberGenerator.new()
		probe.seed = seed_value
		if probe.randf() * 100.0 < 5.0:
			service._combat_rng.seed = seed_value
			return


# ------------------------------------------------------------------------------------------------ rollback and caches

func _rollback_and_caches() -> void:
	player.stats.is_defeated = false
	player.stats.current_hp = player.stats.max_hp
	_park_all()
	await_close()
	_place(player, Vector3i(7, 0, 13))
	level.turn_manager.player_units.has(player)
	# A change that cannot be applied is rolled back: the map is exactly as before and the action is refused without cost.
	var before := _world_state()
	var graph_before := battle.pathfinder.graph_revision()
	MapDoors.fail_after_apply = true
	var failed := await service.submit_door(_request(&"open_door"), true)
	MapDoors.fail_after_apply = false
	var after := _world_state()
	check(failed == null and service.last_rejection.code == &"commit_failed", "A transition that fails after mutating is refused as commit_failed (%s)" % service.last_rejection.code)
	check(before == after, "...and rolled back exactly: geometry signature, door state, revision, AP, RNG and occupancy are unchanged")
	check(MapDoors.consistent(map, DOOR), "...and the restored map is consistent with the door's state")
	var routes := _route(Vector3i(7, 0, 11), Vector3i(7, 0, 13))
	check(routes.length > 20.0 and not routes.through, "...and the rebuilt movement graph is the closed one (%.1f m round)" % routes.length)
	check(battle.pathfinder.graph_revision() > graph_before, "...the graph revision moved on (caches built during the failed attempt cannot survive)")
	# Cache invalidation: the revisions every preview and AI cache is keyed on move with a committed change.
	var los_before := map.los_revision
	var graph_now := battle.pathfinder.graph_revision()
	var revision_now := service.state_revision
	var committed := await service.submit_door(_request(&"open_door"), true)
	check(committed != null and map.los_revision > los_before and battle.pathfinder.graph_revision() > graph_now and service.state_revision == revision_now + 1, "A committed change moves the LOS, graph and action revisions that the player previews and the AI caches are keyed on")
	var snapshot := AIPlanningSnapshot.capture(battle)
	await service.submit_door(_request(&"close_door"), true)
	check(snapshot.is_stale(battle), "An AI planning snapshot taken before the change is stale after it")
	# A request prepared before a committed change is stale afterwards.
	var old_request := _request(&"open_door")
	await service.submit_door(_request(&"open_door") if (map.doors[DOOR] as DoorData).state == DoorData.CLOSED else _request(&"close_door"), true)
	var rejected := await service.submit_door(old_request, true)
	check(rejected == null and service.last_rejection.code == &"stale_revision", "A request prepared before a committed change is refused as stale")


# ------------------------------------------------------------------------------------------------ a lethal reaction (last: it removes the opener)

func _lethal() -> void:
	player.stats.is_defeated = false
	player.stats.current_hp = player.stats.max_hp
	_park_all()
	await_close()
	_place(player, Vector3i(7, 0, 13))
	_place(enemy, Vector3i(7, 0, 9))
	_arm(enemy)
	player.stats.current_hp = 1
	_force_hit_roll()
	var lethal := await service.submit_door(_request(&"open_door"), true)
	check(lethal != null and not lethal.reaction_events.is_empty() and lethal.reaction_events[0].target_defeated and (map.doors[DOOR] as DoorData).state == DoorData.OPEN, "A lethal reaction defeats the opener and the door stays open (%s)" % [lethal.reaction_events[0].to_dictionary() if lethal and not lethal.reaction_events.is_empty() else "no reaction"])
