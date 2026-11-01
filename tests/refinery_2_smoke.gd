extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func signature(data: MapData) -> String:
	var entries: Array[String] = []
	for cell: MapCellData in data.cells.values():
		entries.append("%s:%s:%s:%s:%s" % [cell.grid_position, cell.world_position, cell.walkable, cell.can_stop, cell.cover_height])
	return "|".join(entries).sha256_text()

func _run() -> void:
	var authored := Refinery2Layout.SCENE.instantiate()
	for names in [["HeaderReturnElbow0", "HeaderReturnDrop0_0"], ["HeaderReturnElbow1", "HeaderReturnDrop1_0"], ["DispatchReturnElbow", "DispatchReturnDrop0"], ["BoilerReturnElbow", "BoilerReturnDrop0"]]:
		var elbow := authored.get_node(names[0]) as Node3D
		var drop := authored.get_node(names[1]) as Node3D
		var elbow_transform := elbow.transform * (elbow.get_node("Visual") as Node3D).transform
		var drop_transform := drop.transform * (drop.get_node("Visual") as Node3D).transform
		check((elbow_transform * Vector3(-0.4, 0.5, -1.4)).distance_to(drop_transform * Vector3(1, 0.5, 0)) < 0.002, "Measured elbow outlet meets drop inlet: %s" % names[0])
	authored.free()
	var started := Time.get_ticks_msec()
	var data := Refinery2Layout.generate(17)
	check(signature(data) == signature(Refinery2Layout.generate(17)), "Same input reproduces authored cells")
	check(signature(data) == signature(Refinery2Layout.generate(91)), "Fixed authored structures do not shuffle across seeds")
	var graph := Pathfinder.new()
	MapGraphBuilder.build(data, graph)
	MissionZonePlanner.populate_defaults(data, graph)
	var validation := MapValidator.validate(data, graph, {TacticalUnit.Faction.PLAYER: 5, TacticalUnit.Faction.ENEMY: 5, TacticalUnit.Faction.ALLY: 5})
	check(validation.is_valid(), validation.describe())
	for cell in [Vector3i(25, 0, 19), Vector3i(14, 0, 47), Vector3i(63, 0, 52)]:
		check(not data.get_cell(cell).walkable, "Hall/tank/warehouse footprint blocks movement: %s" % cell)
	for cell in [Vector3i(7, 0, 20), Vector3i(88, 0, 20), Vector3i(50, 0, 38), Vector3i(50, 0, 73)]:
		check(data.get_cell(cell).can_stop, "Service roads remain open: %s" % cell)
	var player := data.get_spawn_cells(TacticalUnit.Faction.PLAYER)[0]
	var enemy := data.get_spawn_cells(TacticalUnit.Faction.ENEMY)[0]
	check(not graph.calculate_3d_path(player, enemy).is_empty(), "Opposing deployments connect naturally")
	for link in data.traversal_links:
		check(not graph.calculate_3d_path(player, link.from_cell).is_empty(), "Each ladder is reachable from deployment")
		check(not graph.calculate_3d_path(link.from_cell, link.to_cell).is_empty(), "Walkway can be climbed")
		check(not graph.calculate_3d_path(link.to_cell, link.from_cell).is_empty(), "Walkway can be descended")
	check(data.traversal_links.size() == 5, "Connected gallery network has five authored ladder accesses")
	for link in data.traversal_links:
		check(not graph.calculate_3d_path(data.traversal_links[0].to_cell, link.to_cell).is_empty(), "Every catwalk access belongs to the connected network")
	check(data.get_inspectable_elevation_levels() == [0, 4], "Walkway uses existing elevation controls")
	for id in [&"reach", &"terminal", &"extract", &"rescue_spawn"]:
		check(not data.get_objective_zone(id).is_empty(), "Shared mission planner supplies %s" % id)
	check(data.get_cell(Vector3i(25, 0, 41)).cover_type == MapCellData.CoverType.LOW, "Thin containment lip is vaultable cover, not invisible to tactics")
	check(data.get_cell(Vector3i(41, 3, 45)).blocks_line_of_sight, "Walkway slab blocks shots through its floor")
	var scaled := Refinery2Layout.generate(17, 2.0)
	check(scaled.get_cell(Vector3i(25, 0, 19)).cover_height == data.get_cell(Vector3i(25, 0, 19)).cover_height * 2, "Cell size scales visual/authoritative height together")
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.refinery_2 = true
	config.map_size = data.map_size
	var recording := BattleReplayRecording.new()
	recording.configuration = config.to_replay()
	var restored := BattleReplayRecording.from_dictionary(JSON.parse_string(JSON.stringify(recording.to_dictionary())))
	var restored_config := BattleConfiguration.new()
	restored_config.apply_replay(restored.configuration)
	check(restored_config.refinery_2 and not restored_config.refinery, "JSON replay preserves distinct authored-map selection")
	var battle := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	battle.configure_battle(restored_config)
	root.add_child(battle)
	await process_frame
	await process_frame
	check(battle.battle_initialization_succeeded, "Restored configuration activates through common battle path")
	check(battle.active_generated_map != null and battle.active_generated_map.source_kind == Refinery2Layout.SOURCE_KIND, "Restoration cannot silently fall back to random map")
	check(battle.get_node_or_null("GeneratedTerrain/Refinery2/PrimaryProcessHall") != null, "Downloaded assets render through authored scene")
	if battle.battle_initialization_succeeded:
		var actor: TacticalUnit = battle.turn_manager.player_units[0]
		var service := battle.battle_controller.action_service
		var moved := await service.submit_move(service.make_move_request(actor, Vector3i(7, 0, 35), TacticalActionRequest.Source.PLAYER), true)
		check(moved != null, "Real movement commits from authored deployment: %s" % (service.last_rejection.code if service.last_rejection else "accepted"))
		var live_recording: BattleReplayRecording = battle._replay_recorder.recording
		check(live_recording.actions.size() == 1, "Movement is recorded once")
		var round_trip := BattleReplayRecording.from_dictionary(JSON.parse_string(JSON.stringify(live_recording.to_dictionary())))
		battle.queue_free()
		await process_frame
		await process_frame
		var playback := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
		playback.configure_replay(round_trip)
		root.add_child(playback)
		await process_frame
		var player_node := playback.get_node_or_null("BattleReplayPlayer") as BattleReplayPlayer
		check(player_node != null, "Saved authored-map recording activates common replay player")
		if player_node:
			player_node.set_playback_speed(4.0)
			var deadline := Time.get_ticks_msec() + 15000
			while not player_node.playback_complete and Time.get_ticks_msec() < deadline:
				await process_frame
			check(player_node.playback_succeeded and player_node.verified_actions == 1, "Restored movement and complete state agree action-by-action")
		playback.queue_free()
	else:
		battle.queue_free()
	await process_frame
	print("Refinery 2 smoke: %d failure(s), %d ms" % [failures, Time.get_ticks_msec() - started])
	quit(1 if failures else 0)
