extends SceneTree

const BATTLE_SCENE := preload("res://levels/prototype_map/prototype_map.tscn")
const ReplaySession := preload("res://systems/replay/battle_replay_session.gd")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 20.0
	ReplaySession.last_recording = null
	var original := await _create_battle(null)
	original.battle_controller.set_debug_player_ai(true)
	await _wait_for_battle(original, 90.0)
	_check(original.turn_manager.battle_result != TurnManager.BattleResult.ONGOING, "Original rescue battle completes")
	_check(ReplaySession.has_recording(), "Completed rescue battle stores a replay")
	var recording = ReplaySession.last_recording
	if recording:
		_check(recording.actions.any(func(action: Dictionary): return String(action.get("expected_state", "")).contains("RescueTarget")), "Replay captures the rescued VIP state")
		var previous_state := recording.initial_state_fingerprint
		for record: Dictionary in recording.actions:
			_check(record.get("expected_state", "") != previous_state, "Automatic mission consequences are recorded once with their parent action")
			previous_state = record.get("expected_state", "")
	original.queue_free()
	await process_frame
	await process_frame

	if recording:
		var replay := await _create_battle(recording)
		var replay_player := replay.get_node("BattleReplayPlayer")
		replay_player.action_delay = 0.01
		await _wait_for_replay(replay_player, 90.0)
		_check(replay_player.playback_succeeded, "Rescue replay completes without divergence")
		_check(replay_player.verified_actions == recording.actions.size(), "Rescue replay verifies every recorded action")
		replay.queue_free()
		await process_frame
	Engine.time_scale = previous_time_scale
	print("Rescue battle replay smoke: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _create_battle(recording) -> BattleLevel:
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	if recording:
		level.configure_replay(recording)
	else:
		level.configure(
			5, 5, true, 372339682, 2, Vector2i(40, 30), false,
			MissionActor.VIPBehavior.PLAYER_CONTROLLED,
			MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.RESCUE, 5, false),
			AIDifficultyPolicy.Tier.NORMAL, true
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
