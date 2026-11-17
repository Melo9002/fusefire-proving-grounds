extends SceneTree
## Real unmodified current-map recording: Shield -> Skip must retain its stance.
const BattleScene := preload("res://levels/prototype_map/prototype_map.tscn")
var failures := 0
var checks := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.TACTICAL_TEST_RANGE)
	config.player_count = 1
	config.enemy_count = 1
	config.player_archetypes = [&"shieldbearer"]
	config.content_manifest = {"population_enabled": false}
	var original := BattleScene.instantiate() as BattleLevel
	original.configure_battle(config)
	root.add_child(original)
	check(original.battle_initialization_succeeded, "Unmodified current range initializes")
	if not original.battle_initialization_succeeded:
		original.free()
		quit(1)
		return
	var actor := original.turn_manager.player_units[0]
	var enemy := original.turn_manager.enemy_units[0]
	var service := original.battle_controller.action_service
	var shield := await service.submit_shield(service.make_shield_request(actor, enemy, TacticalActionRequest.Source.PLAYER), true)
	var skipped := await service.submit_simple(service.make_simple_request(&"wait", actor, TacticalActionRequest.Source.PLAYER), true)
	check(shield != null and skipped != null and actor.tactical_state.is_shielding and actor.stats.current_ap == 0, "Shield then Skip keeps the original protection with no remaining AP")
	var facing := actor.tactical_state.shield_facing
	var expected_log := original.battle_controller.combat_log.duplicate()
	var path := "res://.godot/defensive-actions-test.replay.json"
	var recording: BattleReplayRecording = original._replay_recorder.recording
	check(recording.actions.size() == 2 and recording.save_json(path) == OK, "Save exact Shield/Skip decisions without editing actors or geometry")
	var loaded := BattleReplayRecording.load_json(path)
	check(loaded.is_playable(), "The saved current simulation validates")
	original.queue_free()
	await process_frame
	await process_frame
	var replay := BattleScene.instantiate() as BattleLevel
	replay.configure_replay(loaded)
	root.add_child(replay)
	check(replay.battle_initialization_succeeded, "Saved current content reconstructs")
	if replay.battle_initialization_succeeded:
		var player := replay.get_node("BattleReplayPlayer") as BattleReplayPlayer
		player.set_playback_speed(4)
		var deadline := Time.get_ticks_msec() + 10000
		while not player.playback_complete and Time.get_ticks_msec() < deadline:
			await process_frame
		check(player.playback_succeeded and player.verified_actions == 2, "Replay verifies both exact actions: %s" % player.last_divergence)
		var replay_actor := replay.turn_manager.player_units[0]
		check(replay_actor.tactical_state.is_shielding and replay_actor.tactical_state.shield_facing.is_equal_approx(facing) and replay_actor.stats.current_ap == 0, "Playback preserves the committed physical facing, Shield and spent AP")
		check(replay.battle_controller.combat_log == expected_log, "Playback regenerates the same Shield/Skip explanation")
	replay.queue_free()
	await process_frame
	await process_frame
	DirAccess.remove_absolute(path)
	print("Defensive action replay: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
