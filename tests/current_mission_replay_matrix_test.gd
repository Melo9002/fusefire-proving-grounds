extends SceneTree
## Bounded current-content coverage before retiring more mechanics fixtures:
## every mission initializes and replays a real committed action on both layouts of all current sites.
const BattleScene = preload("res://levels/prototype_map/prototype_map.tscn")
var failures := 0
var cases := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	for battlefield_id in BattlefieldCatalog.PLAYABLE:
		for map_seed in [16, 17]:
			for preset in MissionCatalog.PRESETS:
				await _case(battlefield_id, map_seed, int(preset.kind))
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
		var player := replay.get_node("BattleReplayPlayer") as BattleReplayPlayer
		for frame in 600:
			if player.playback_complete: break
			await process_frame
		check(player.playback_complete and player.playback_succeeded and player.verified_actions == restored.actions.size(), context + " replays without divergence: " + player.last_divergence)
	replay.queue_free()
	await process_frame
