extends SceneTree
## Bounded current-content coverage before retiring more mechanics fixtures:
## every mission initializes and replays a real committed action on both layouts of all current sites.
const BattleScene = preload("res://levels/prototype_map/prototype_map.tscn")
const Scenery = preload("res://tests/fixtures/world_scenery_snapshot.gd")
var failures := 0
var cases := 0
var output := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		if args.size() != 2 or args[0] != "capture" or DisplayServer.get_name() == "headless":
			push_error("Use a graphics run with -- capture <output-directory>, or no arguments for all 48 cases")
			quit(1)
			return
		output = args[1]
		DirAccess.make_dir_recursive_absolute(output)
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	# The ordinary suite always runs all 48 cases. Explicit capture mode reviews
	# only the two Depot Eliminate layouts, retaining every per-case assertion.
	var sites: Array = BattlefieldCatalog.PLAYABLE if output.is_empty() else [BattlefieldCatalog.SERVICE_DEPOT]
	var missions: Array = MissionCatalog.PRESETS if output.is_empty() else [MissionCatalog.PRESETS[0]]
	for battlefield_id in sites:
		for map_seed in [16, 17]:
			for preset in missions:
				await _case(battlefield_id, map_seed, int(preset.kind))
	Scenery.clear_cache()
	print("Current mission/replay matrix: %d cases, %d failure(s)" % [cases, failures])
	quit(1 if failures else 0)

func _case(battlefield_id: StringName, map_seed: int, kind: int) -> void:
	cases += 1
	var context := "%s seed %d, %s" % [BattlefieldCatalog.label(battlefield_id), map_seed, MissionObjectiveDefinition.Kind.keys()[kind]]
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(battlefield_id)
	config.battle_seed = map_seed
	config.include_vip = kind == MissionObjectiveDefinition.Kind.PROTECT
	config.ally_count = 1 if kind in [MissionObjectiveDefinition.Kind.PROTECT, MissionObjectiveDefinition.Kind.RESCUE] else 0
	config.mission = MissionCatalog.create_mission(kind, config.enemy_count, config.include_vip)
	config.content_manifest = {"population_enabled": kind % 2 == 0}
	var live := BattleScene.instantiate() as BattleLevel
	live.configure_battle(config)
	root.add_child(live)
	for frame in 240:
		if live.battle_initialization_succeeded or not live.battle_initialization_errors.is_empty(): break
		await process_frame
	check(live.battle_initialization_succeeded, context + " initializes with validated deployments/objectives: " + str(live.battle_initialization_errors))
	if not live.battle_initialization_succeeded:
		live.free()
		return
	check(live.battle_controller.last_map_validation.is_valid(), context + " passes tactical map validation")
	_check_placements(live, context)
	var scenery := Scenery.capture(live.get_node("GeneratedTerrain").get_child(0))
	check(scenery.meshes > 0, context + " records actual surrounding meshes")
	var atmosphere := _atmosphere(live)
	await _capture(live, "%s-%d-live" % [battlefield_id, map_seed])
	check(await live.battle_controller.try_aim(live.turn_manager.active_unit), context + " commits an authoritative action")
	var recording = live._replay_recorder.recording
	var restored := BattleReplayRecording.from_dictionary(JSON.parse_string(JSON.stringify(recording.to_dictionary())))
	check(restored.is_playable(), context + " serializes a playable exact-content recording: " + restored.validation_message())
	var manifest := live.active_generated_map.content_manifest.duplicate(true)
	live.queue_free()
	await process_frame
	var replay := BattleScene.instantiate() as BattleLevel
	replay.configure_replay(restored)
	root.add_child(replay)
	for frame in 240:
		if replay.battle_initialization_succeeded or not replay.battle_initialization_errors.is_empty(): break
		await process_frame
	check(replay.battle_initialization_succeeded, context + " reconstructs the recorded battlefield")
	if replay.battle_initialization_succeeded:
		check(replay.active_generated_map.content_manifest == manifest, context + " preserves exact parcels and population")
		check(Scenery.capture(replay.get_node("GeneratedTerrain").get_child(0)) == scenery and _atmosphere(replay) == atmosphere, context + " reconstructs identical fixed scenery and atmosphere")
		await _capture(replay, "%s-%d-replay" % [battlefield_id, map_seed])
		var player := replay.get_node("BattleReplayPlayer") as BattleReplayPlayer
		for frame in 600:
			if player.playback_complete: break
			await process_frame
		check(player.playback_complete and player.playback_succeeded and player.verified_actions == restored.actions.size(), context + " replays without divergence: " + player.last_divergence)
	replay.queue_free()
	await process_frame

func _check_placements(level: BattleLevel, context: String) -> void:
	var map := level.active_generated_map
	var graph := level.battle_controller.pathfinder
	for unit in level.battle_controller.grid_manager.occupancy_map.values():
		check(map.has_cell(unit.grid_position), context + " deploys every actor inside tactical data")
	for zone: MapZoneData in map.zones.values():
		for cell in zone.cells:
			check(map.has_cell(cell) and graph.grid_to_id_map.has(cell), context + " keeps deployment/objective/extraction zones on the map: " + String(zone.zone_id))
	for terminal_id in level.objective_manager.get_terminal_ids():
		var state := level.objective_manager.get_terminal_state(terminal_id)
		check(map.has_cell(state.definition.grid_position), context + " keeps terminal positions in tactical data")
	for footprint in map.transport_footprints.values():
		for cell in footprint: check(map.has_cell(cell), context + " keeps extraction transport footprints on-map")

func _atmosphere(level: BattleLevel) -> Array:
	var environment := level.world_environment.environment
	return [environment.background_color, environment.ambient_light_color, environment.ambient_light_energy, environment.fog_enabled, environment.fog_density, environment.fog_light_color]

func _capture(level: BattleLevel, title: String) -> void:
	if output.is_empty(): return
	var rig := level.get_node("CameraRig") as TacticalCamera
	rig.set_process(false)
	rig._cancel_selection_focus()
	rig.camera.global_position = Vector3(24, 38, 46)
	rig.camera.look_at(Vector3.ZERO)
	rig.camera.fov = 46
	level.get_node("Visualizers/GridVisualizer").hide()
	level.get_node("Visualizers/GridCursor").hide()
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(title + ".png")) == OK, "Capture " + title)
