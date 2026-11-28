extends SceneTree
## Milestone 06.09 (acceptance): door-induced Guard reactions through the whole recorded path. A real sequence on the Interaction Range: the player takes position and sets Guard, the enemy walks to the door and
## opens it (a newly legal shot: the reaction fires from inside the door transaction), repeating each round until a reaction defeats the opener. The current-version recording then replays in a fresh battle and must
## reproduce RNG state, HP, supply, Guard consumption, the actor's removal, the door state, every action result and the fingerprints.
const Catalog := preload("res://systems/generation/battlefield_catalog.gd")
const Scene := preload("res://levels/prototype_map/prototype_map.tscn")
const DOOR := &"door_a"
const WATCH := Vector3i(7, 0, 9)
const POST := Vector3i(7, 0, 13)
var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func _config() -> BattleConfiguration:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(Catalog.INTERACTION_RANGE)
	config.player_count = 1
	config.enemy_count = 1
	config.battle_seed = int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 4   # seed 4: four consecutive hits, so the fourth reaction is lethal; other even seeds exist where the shots miss
	config.content_manifest = {"population_enabled": false}
	return config


func _move_to(level: BattleLevel, unit: TacticalUnit, cell: Vector3i) -> bool:
	var service := level.battle_controller.action_service
	var guard := 0
	while level.battle_controller.grid_manager.get_unit_grid(unit) != cell and guard < 8:
		guard += 1
		var result := await service.submit_move(service.make_move_request(unit, cell, TacticalActionRequest.Source.AI), true)
		if result == null:
			print("move rejected: ", service.last_rejection.code, " ", service.last_rejection.message)
			return false
	return level.battle_controller.grid_manager.get_unit_grid(unit) == cell


func _end_turn_if_active(level: BattleLevel, unit: TacticalUnit) -> void:
	if level.turn_manager.active_unit == unit and level.turn_manager.battle_result == TurnManager.BattleResult.ONGOING:
		level.turn_manager.end_current_turn()
		await process_frame


func _play(recording: BattleReplayRecording) -> BattleLevel:
	var replay := Scene.instantiate() as BattleLevel
	replay.configure_replay(recording)
	root.add_child(replay)
	return replay


func _finish(replay: BattleLevel) -> BattleReplayPlayer:
	var player := replay.get_node("BattleReplayPlayer") as BattleReplayPlayer
	player.set_playback_speed(8)
	var deadline := Time.get_ticks_msec() + 30000
	while not player.playback_complete and Time.get_ticks_msec() < deadline:
		await process_frame
	return player


func _run() -> void:
	var original := Scene.instantiate() as BattleLevel
	original.configure_battle(_config())
	root.add_child(original)
	await create_timer(0.3).timeout
	check(original.battle_initialization_succeeded, "The Interaction Range initializes")
	for node in original.find_children("*AI", "AIController", true, false):
		node.queue_free()
	await process_frame
	var turn := original.turn_manager
	var battle := original.battle_controller
	var service := battle.action_service
	var map := battle.grid_manager.map_data
	var door: DoorData = map.doors[DOOR]
	var watcher: TacticalUnit = turn.player_units[0]
	var opener: TacticalUnit = turn.enemy_units[0]
	print("player ", watcher.tactical_id, " hp ", watcher.stats.current_hp, " enemy ", opener.tactical_id, " hp ", opener.stats.current_hp, " phase ", turn.current_phase, " active ", turn.active_unit)
	var rounds := 0
	var reactions := 0
	var sequence: Array = []
	while not opener.stats.is_defeated and rounds < 12 and turn.battle_result == TurnManager.BattleResult.ONGOING:
		rounds += 1
		if turn.active_unit != watcher:
			check(false, "Round %d: the player is not active (%s, phase %s)" % [rounds, turn.active_unit, turn.current_phase])
			break
		if rounds == 1:
			check(await _move_to(original, watcher, WATCH), "The player walks to the watch cell")
		var guard := await service.submit_overwatch(service.make_overwatch_request(watcher, TacticalActionRequest.Source.PLAYER), true)
		check(guard != null or watcher.tactical_state.is_overwatching, "Round %d: the player sets Guard" % rounds)
		await _end_turn_if_active(original, watcher)
		if turn.active_unit != opener:
			check(false, "Round %d: the enemy is not active (%s)" % [rounds, turn.active_unit])
			break
		if rounds == 1:
			check(await _move_to(original, opener, POST), "The enemy walks to the door")
		var hp_before := opener.stats.current_hp
		var opened := await service.submit_door(service.make_door_request(&"open_door", opener, DOOR, TacticalActionRequest.Source.AI), true)
		check(opened != null, "Round %d: the enemy opens the door (%s)" % [rounds, "" if opened != null else service.last_rejection.message])
		if opened == null:
			break
		reactions += opened.reaction_events.size()
		sequence.append({"round": rounds, "events": opened.reaction_events.size(), "hp_before": hp_before, "hp_after": opener.stats.current_hp, "defeated": opener.stats.is_defeated})
		if opener.stats.is_defeated:
			break
		var closed := await service.submit_door(service.make_door_request(&"close_door", opener, DOOR, TacticalActionRequest.Source.AI), true)
		check(closed != null and closed.reaction_events.is_empty(), "Round %d: closing provokes nothing" % rounds)
		await _end_turn_if_active(original, opener)
	print("sequence ", sequence)
	check(opener.stats.is_defeated, "A door-induced Guard reaction defeated the opener within %d rounds (%d reactions)" % [rounds, reactions])
	check(reactions >= 1 and door.state == DoorData.OPEN, "The door stays open after the lethal reaction")
	var expected := {
		"rng": service.get_combat_rng_state(), "door": door.state, "signature": SurfaceNavigation.signature(map),
		"watcher_hp": watcher.stats.current_hp, "watcher_supply": watcher.stats.current_supply_points, "watcher_guard": watcher.tactical_state.is_overwatching,
		"opener_hp": opener.stats.current_hp, "opener_defeated": opener.stats.is_defeated, "result": int(turn.battle_result), "revision": service.state_revision,
	}
	var recording: BattleReplayRecording = original._replay_recorder.recording
	var door_records := recording.actions.filter(func(record): return String(record.get("kind", "")) in ["open_door", "close_door"])
	var reaction_records := door_records.filter(func(record): return not (record.get("resolved", {}).get("reaction_events", []) as Array).is_empty())
	check(not reaction_records.is_empty(), "The recording carries door records with reaction events (%d of %d)" % [reaction_records.size(), door_records.size()])
	check(recording.simulation_version == BattleReplayRecording.version_for_configuration(recording.configuration), "Recorded under the current simulation version (%s)" % recording.simulation_version)
	var path := "res://.godot/dynamic-door-guard.replay.json"
	check(recording.save_json(path) == OK, "The recording saves")
	var loaded := BattleReplayRecording.load_json(path)
	check(loaded.is_playable(), "The saved recording validates")
	original.queue_free()
	await process_frame
	await process_frame
	var replay := _play(loaded)
	check(replay.battle_initialization_succeeded, "The replay battle reconstructs")
	if replay.battle_initialization_succeeded:
		var player := await _finish(replay)
		check(player.playback_succeeded and player.verified_actions == loaded.actions.size(), "Playback verifies every action (%d of %d): %s" % [player.verified_actions, loaded.actions.size(), player.last_divergence])
		var r_service := replay.battle_controller.action_service
		var r_map := replay.battle_controller.grid_manager.map_data
		var r_watcher: TacticalUnit = replay.turn_manager.player_units[0]
		var r_opener: TacticalUnit = replay.turn_manager.enemy_units[0] if not replay.turn_manager.enemy_units.is_empty() else null
		check(r_service.get_combat_rng_state() == expected.rng, "RNG state matches the original")
		check((r_map.doors[DOOR] as DoorData).state == expected.door and SurfaceNavigation.signature(r_map) == expected.signature, "Door state and geometry match")
		check(r_watcher.stats.current_hp == expected.watcher_hp and r_watcher.stats.current_supply_points == expected.watcher_supply and r_watcher.tactical_state.is_overwatching == expected.watcher_guard, "The watcher's HP, supply and Guard match (Guard consumed by the reaction)")
		check(r_opener == null or (r_opener.stats.is_defeated == expected.opener_defeated and r_opener.stats.current_hp == expected.opener_hp), "The opener's HP and removal match")
		check(int(replay.turn_manager.battle_result) == expected.result and r_service.state_revision == expected.revision, "Battle result and action revision match")
	replay.queue_free()
	await process_frame
	await process_frame
	var tampered := BattleReplayRecording.load_json(path)
	for record in tampered.actions:
		if String(record.get("kind", "")) == "open_door" and not (record.get("resolved", {}).get("reaction_events", []) as Array).is_empty():
			var events: Array = record.resolved.reaction_events
			if events[0] is Dictionary:
				events[0]["target_defeated"] = not bool(events[0].get("target_defeated", false))
			break
	var bad := _play(tampered)
	var bad_player := await _finish(bad)
	check(not bad_player.playback_succeeded, "Control: a tampered reaction outcome is detected (%s)" % bad_player.last_divergence)
	bad.queue_free()
	await process_frame
	DirAccess.remove_absolute(path)
	print("dynamic_door_guard_replay_test: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures > 0 else 0)
