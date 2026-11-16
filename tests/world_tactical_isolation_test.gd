extends SceneTree
## Outside scenery is never a tactical destination or selectable/shootable actor.
const Fingerprint = preload("res://systems/replay/battle_state_fingerprint.gd")
const Scenery = preload("res://tests/fixtures/world_scenery_snapshot.gd")
var failures := 0
var edge_cases := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	_check_fixed_scenery()
	for site in BattlefieldCatalog.PLAYABLE:
		for map_seed in [16, 17]: await _case(site, map_seed)
	Scenery.clear_cache()
	print("World tactical isolation: %d edge cases, %d failure(s)" % [edge_cases, failures])
	quit(1 if failures else 0)

func _place(unit: TacticalUnit, cell: Vector3i, grid: GridManager) -> void:
	grid.update_unit_position(unit, unit.grid_position, cell)
	unit.global_position = grid.grid_to_world(cell) + Vector3.UP * unit.standing_height

func _case(site: StringName, map_seed: int) -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(site)
	config.battle_seed = map_seed
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.EXTRACT, 2)
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	check(level.battle_initialization_succeeded, "Isolation case starts a validated current-site battle")
	if not level.battle_initialization_succeeded:
		level.free()
		return
	var rig := level.get_node("CameraRig") as TacticalCamera
	rig.set_process(false)
	rig._cancel_selection_focus()
	rig.camera.global_position = Vector3(0, 65, 1)
	rig.camera.look_at(Vector3.ZERO)
	rig.camera.fov = 70
	var picker := level.get_node("Systems/MouseRaycaster") as MouseRaycaster
	var grid := level.battle_controller.grid_manager
	var graph := level.battle_controller.pathfinder
	var service := level.battle_controller.action_service
	var actor := level.turn_manager.active_unit
	var target := level.turn_manager.enemy_units[0]
	var outside: Array[Vector3i] = []
	for offset in range(-1, 41):
		outside.append_array([Vector3i(-1, 0, offset), Vector3i(40, 0, offset), Vector3i(offset, 0, -1), Vector3i(offset, 0, 40)])
	for cell in outside:
		check(grid.get_cell_data(cell) == null and not graph.grid_to_id_map.has(cell) and not grid.can_unit_occupy_cell(actor, cell), "No outside cell enters the map or movement graph")
		check(not service.query_move(actor.tactical_id, cell).is_legal(), "Outside move query rejects: " + str(cell))
	for direction in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
		edge_cases += 1
		var anchor := Vector3i(-1, -1, -1)
		var tangent := Vector3i(-direction.z, 0, direction.x)
		for offset in range(1, 39):
			var cell := Vector3i(0 if direction.x < 0 else 39, 0, offset) if direction.x != 0 else Vector3i(offset, 0, 0 if direction.z < 0 else 39)
			var candidates := [cell, cell - direction, cell + tangent]
			if candidates.all(func(candidate): return grid.can_unit_occupy_cell(actor, candidate) and grid.get_cell_data(candidate).cover_type == MapCellData.CoverType.NONE):
				anchor = cell
				break
		check(anchor.y == 0, "Each edge has a usable controlled approach")
		if anchor.y != 0: continue
		_place(actor, anchor, grid)
		_place(target, anchor - direction, grid)
		# Controlled boarding-zone query at each edge; normal mission placement
		# and real transport footprints are checked separately in the mission matrix.
		grid.map_data.set_objective_zone(&"extract", [anchor])
		check(service.query_mission(&"extract", actor.tactical_id).is_legal(), "An inside edge boarding cell permits extraction")
		grid.map_data.set_objective_zone(&"extract", [anchor - direction])
		check(not service.query_mission(&"extract", actor.tactical_id).is_legal(), "Standing outside the boarding zone does not extract")
		await physics_frame
		await physics_frame
		check(service.query_move(actor.tactical_id, anchor + tangent).is_legal(), "An inside step remains legal beside the edge")
		check(service.query_attack(actor.tactical_id, target.tactical_id).is_legal(), "An inside target remains shootable beside the edge")
		check(picker.get_unit_under_mouse(rig.camera.unproject_position(target.global_position)) == target, "Inside target picking is a positive control")
		var beyond: Vector3i = anchor + direction
		var before := Fingerprint.capture(level.turn_manager, grid, level.objective_manager)
		var move_result = await service.submit_move(TacticalActionRequest.move(actor.tactical_id, beyond, service.state_revision, TacticalActionRequest.Source.PLAYER))
		check(move_result == null, "An outside move cannot commit")
		check(Fingerprint.capture(level.turn_manager, grid, level.objective_manager) == before, "Rejected outside movement spends no AP and moves nobody")
		_place(target, beyond, grid) # Deliberately stale actor fixture; normal deployment never does this.
		await physics_frame
		await physics_frame
		var query := service.query_attack(actor.tactical_id, target.tactical_id)
		check(not query.is_legal() and query.validation.code == &"outside_battlefield", "Registered off-map target is rejected explicitly")
		if not query.is_legal():
			before = Fingerprint.capture(level.turn_manager, grid, level.objective_manager)
			var attack_result = await service.submit_attack(TacticalActionRequest.attack(actor.tactical_id, target.tactical_id, service.state_revision, TacticalActionRequest.Source.PLAYER))
			check(attack_result == null, "An outside attack cannot commit")
			check(Fingerprint.capture(level.turn_manager, grid, level.objective_manager) == before, "Rejected outside attack changes no AP, HP or occupancy")
		var screen := rig.camera.unproject_position(target.global_position)
		check(picker.get_unit_under_mouse(screen) == null, "Off-map actors are not mouse targets")
		check(picker.get_floor_candidates(screen).is_empty(), "Continuing outside ground is not a mouse destination")
		_place(target, anchor - direction, grid)
		var preview := CombatRules.evaluate_attack_from_cell(actor, beyond, target, grid, level.get_world_3d())
		check(not preview.is_legal and preview.reason == "Outside battlefield", "Outgoing prediction rejects an outside firing cell")
		var scenery_target := service.query_attack(actor.tactical_id, &"EastWorkshop")
		check(not scenery_target.is_legal(), "Scenery names never become actor targets")
	level.queue_free()
	await process_frame

func _check_fixed_scenery() -> void:
	var plots := {}
	for site in BattlefieldCatalog.PLAYABLE:
		for map_seed in range(16, 24):
			for population in [false, true]:
				var data := BattlefieldCatalog.generate(site, Vector2i.ZERO, map_seed, 1.0, {"population_enabled": population})
				var host := Node3D.new()
				root.add_child(host)
				check(BattlefieldCatalog.present(data, host, 1.0), "Known seed presents fixed plot surroundings")
				var plot := host.get_child(0)
				var signature := Scenery.capture(plot)
				check(signature.meshes > 0, "Scenery comparison includes actual meshes")
				var id: StringName = data.content_manifest.plot_id
				if plots.has(id): check(plots[id] == signature, "Population and seed changes do not randomize surroundings within a plot")
				else: plots[id] = signature
				var original: Transform3D = plot.get_node("Distant").transform
				plot.get_node("Distant").position.x += 1.0
				check(Scenery.capture(plot) != signature, "Appearance evidence detects a real scenery transform change")
				plot.get_node("Distant").transform = original
				check(Scenery.capture(plot) == signature, "Restoring authored scenery restores its appearance evidence")
				host.free()
	check(plots.size() == 6, "Both fixed layouts of all three sites are exercised")
	check(plots[&"depot_loading_crossing"] != plots[&"depot_service_spine"], "Different plots retain their own visible frontage")
