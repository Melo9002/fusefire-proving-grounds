extends SceneTree
## Milestone 06.09 replay policy: a current-version recording of real door actions (moves and door changes through the action service) reproduces exactly in a fresh battle: the same transitions, the same geometry
## after each, AP, RNG state and fingerprints; a recording whose door result is tampered with diverges; recordings of the previous simulation versions are rejected by name (no migration is kept).
const Catalog := preload("res://systems/generation/battlefield_catalog.gd")
const Scene := preload("res://levels/prototype_map/prototype_map.tscn")
const DOOR := &"door_a"
var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func _config(map_seed: int) -> BattleConfiguration:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(Catalog.INTERACTION_RANGE)
	config.player_count = 1
	config.enemy_count = 1
	config.battle_seed = map_seed
	config.content_manifest = {"population_enabled": false}
	return config


func _play(recording: BattleReplayRecording) -> BattleLevel:
	var replay := Scene.instantiate() as BattleLevel
	replay.configure_replay(recording)
	root.add_child(replay)
	return replay


func _wait_for(replay: BattleLevel) -> BattleReplayPlayer:
	var player := replay.get_node("BattleReplayPlayer") as BattleReplayPlayer
	player.set_playback_speed(8)
	var deadline := Time.get_ticks_msec() + 20000
	while not player.playback_complete and Time.get_ticks_msec() < deadline:
		await process_frame
	return player


func _run() -> void:
	var original := Scene.instantiate() as BattleLevel
	original.configure_battle(_config(2))
	root.add_child(original)
	await create_timer(0.3).timeout
	check(original.battle_initialization_succeeded, "The Interaction Range initializes for recording (door closed)")
	var actor := original.turn_manager.player_units[0]
	var battle := original.battle_controller
	var service := battle.action_service
	var map := battle.grid_manager.map_data
	# Real actions: walk to the door (two cells), open it, close it, open it again.
	var walk := await service.submit_move(service.make_move_request(actor, Vector3i(7, 0, 11), TacticalActionRequest.Source.PLAYER), true)
	check(walk != null and battle.grid_manager.get_unit_grid(actor) == Vector3i(7, 0, 11), "The unit walks to the cell in front of the door")
	var ap_after_walk := actor.stats.current_ap
	var kinds: Array = [&"open_door", &"close_door", &"open_door"]
	var results: Array = []
	for kind in kinds:
		var result := await service.submit_door(service.make_door_request(kind, actor, DOOR, TacticalActionRequest.Source.PLAYER), true)
		check(result != null, "%s commits (%s)" % [kind, "" if result != null else "%s: %s" % [service.last_rejection.code, service.last_rejection.message]])
		if result != null: results.append(result)
	check(results.size() == 3 and actor.stats.current_ap == ap_after_walk, "Three door changes cost no AP (%d before, %d after)" % [ap_after_walk, actor.stats.current_ap])
	var expected_state := (map.doors[DOOR] as DoorData).state
	var expected_signature := SurfaceNavigation.signature(map)
	var expected_rng := service.get_combat_rng_state()
	var recording: BattleReplayRecording = original._replay_recorder.recording
	var door_records := recording.actions.filter(func(record): return String(record.get("kind", "")) in ["open_door", "close_door"])
	check(door_records.size() == 3 and recording.simulation_version == BattleReplayRecording.version_for_configuration(recording.configuration), "The three door changes are recorded under the current simulation version (%s)" % recording.simulation_version)
	check(door_records.size() == 3 and String(door_records[0].resolved.state_after) == "open" and String(door_records[1].resolved.state_after) == "closed" and String(door_records[2].resolved.state_after) == "open", "Each record carries the door's state before and after")
	check(door_records.size() == 3 and door_records[0].resolved.geometry_signature != door_records[1].resolved.geometry_signature and door_records[0].resolved.geometry_signature == door_records[2].resolved.geometry_signature, "...and the geometry signature: open, closed, open (the first and third agree, the second differs)")
	var path := "res://.godot/dynamic-door-test.replay.json"
	check(recording.save_json(path) == OK, "The recording saves")
	var loaded := BattleReplayRecording.load_json(path)
	check(loaded.is_playable(), "The saved current-version recording validates")
	original.queue_free()
	await process_frame
	await process_frame
	# Deterministic playback.
	var replay := _play(loaded)
	check(replay.battle_initialization_succeeded, "The recorded map reconstructs (door state is part of the content manifest and fingerprint)")
	if replay.battle_initialization_succeeded:
		var player := await _wait_for(replay)
		check(player.playback_succeeded and player.verified_actions == loaded.actions.size(), "Playback verifies every action including the door changes: %s" % player.last_divergence)
		var replay_map := replay.battle_controller.grid_manager.map_data
		check((replay_map.doors[DOOR] as DoorData).state == expected_state and SurfaceNavigation.signature(replay_map) == expected_signature, "The replayed door state and the geometry equal the original's")
		check(replay.battle_controller.action_service.get_combat_rng_state() == expected_rng and replay.turn_manager.player_units[0].stats.current_ap == ap_after_walk, "The replayed RNG state and AP equal the original's")
	replay.queue_free()
	await process_frame
	await process_frame
	# Negative control: a recording whose door result was altered diverges.
	var tampered := BattleReplayRecording.load_json(path)
	for record in tampered.actions:
		if String(record.get("kind", "")) == "close_door":
			record.resolved.geometry_signature = "tampered"
	var tampered_replay := _play(tampered)
	var tampered_player := await _wait_for(tampered_replay)
	check(not tampered_player.playback_succeeded and tampered_player.last_divergence.contains("geometry_signature"), "Control: a tampered door result is detected (%s)" % tampered_player.last_divergence)
	tampered_replay.queue_free()
	await process_frame
	await process_frame
	# Historical recordings are rejected by name, not migrated.
	var historical := BattleReplayRecording.load_json(path)
	historical.simulation_version = "prototype-1.5-guaranteed-hit-11"
	check(not historical.is_playable() and historical.validation_message().contains("Incompatible replay simulation"), "A recording of the previous simulation version is rejected clearly: %s" % historical.validation_message())
	DirAccess.remove_absolute(path)
	print("dynamic_door_replay_test: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures > 0 else 0)
