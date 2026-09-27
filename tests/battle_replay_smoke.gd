extends SceneTree

const BATTLE_SCENE := preload("res://levels/prototype_map/prototype_map.tscn")
const ReplaySession := preload("res://systems/replay/battle_replay_session.gd")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 12.0
	ReplaySession.last_recording = null
	var original := await _create_battle(null)
	original.battle_controller.set_debug_player_ai(true)
	await _wait_for_battle(original, 25.0)
	_check(original.turn_manager.battle_result != TurnManager.BattleResult.ONGOING, "Original automated battle completes")
	_check(ReplaySession.has_recording(), "Completed battle stores a playable replay")
	var recording = ReplaySession.last_recording
	if recording:
		_check(not recording.actions.is_empty(), "Replay contains authoritative actions")
		_check(recording.actions.any(func(action: Dictionary): return action.kind == "move"), "Replay records movement")
		_check(recording.actions.any(func(action: Dictionary): return action.kind == "attack"), "Replay records attacks")
	var original_result := original.turn_manager.battle_result
	var hud := original.get_node("Visualizers/BattleUI/TurnHUDController")
	_check(hud.replay_button.visible and hud.setup_button.visible, "Battle end exposes Replay and Return to Match Setup buttons")
	original.queue_free()
	await process_frame
	await process_frame

	if recording:
		var replay := await _create_battle(recording)
		var replay_player := replay.get_node("BattleReplayPlayer")
		var controls := replay.get_node_or_null("Visualizers/BattleUI/ReplayControls")
		_check(controls != null, "Replay creates dedicated playback controls")
		_check(not replay.get_node("Visualizers/BattleUI/UnitPortraitBar").visible, "Replay hides the tactical portrait bar")
		_check(not replay.get_node("Visualizers/BattleUI/ObjectiveHUD").visible, "Replay hides the tactical objective HUD")
		replay_player.set_playback_paused(true)
		var paused_at: int = replay_player.verified_actions
		for _frame in 8:
			await process_frame
		_check(replay_player.verified_actions == paused_at, "Pause holds replay between authoritative actions")
		replay_player.set_playback_speed(4.0)
		replay_player.camera_mode = replay_player.CameraMode.FOLLOW_ACTION
		replay_player.set_playback_paused(false)
		await _wait_for_replay(replay_player, 25.0)
		_check(replay.turn_manager.battle_result == original_result, "Replay reaches the recorded battle result")
		_check(replay.battle_controller.replay_mode, "Replay disables ordinary AI and manual input")
		_check(replay_player.playback_succeeded, "Replay consumes the complete action log without divergence")
		_check(replay_player.verified_actions == recording.actions.size(), "Replay state matches after every recorded action")
		replay.queue_free()
		await process_frame
	Engine.time_scale = previous_time_scale
	print("Battle replay smoke: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _create_battle(recording) -> BattleLevel:
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	if recording:
		level.configure_replay(recording)
	else:
		level.configure(
			2, 2, true, 23001, 0, Vector2i(24, 20), false,
			MissionActor.VIPBehavior.PLAYER_CONTROLLED,
			MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 2, false),
			AIDifficultyPolicy.Tier.NORMAL, false
		)
	root.add_child(level)
	while level.turn_manager.current_round == 0:
		await process_frame
	return level

func _wait_for_battle(level: BattleLevel, timeout_seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while is_instance_valid(level) and level.turn_manager.battle_result == TurnManager.BattleResult.ONGOING and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout

func _wait_for_replay(player: Node, timeout_seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while is_instance_valid(player) and not player.playback_complete and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
