class_name BattleReplayPlayer
extends Node

const StateFingerprint := preload("res://systems/replay/battle_state_fingerprint.gd")
const ReplayControlsData := preload("res://ui/replay_controls.gd")

signal playback_finished(success: bool)
signal playback_progressed(completed: int, total: int)

enum CameraMode { FREE, FOLLOW_ACTION, CINEMATIC }

var recording
var level: BattleLevel
var action_delay := 0.18
var playback_complete := false
var playback_succeeded := false
var verified_actions := 0
var playback_paused := false
var playback_speed := 1.0
var camera_mode: CameraMode = CameraMode.FREE
var _controls: Control
var last_divergence := ""

func begin(p_level: BattleLevel, p_recording) -> void:
	# The player and its controls must remain responsive while the tactical tree is
	# paused so playback can be resumed from the middle of an action.
	process_mode = Node.PROCESS_MODE_ALWAYS
	level = p_level
	recording = p_recording
	var validation: String = "Replay recording is missing" if recording == null else recording.validation_message()
	if not validation.is_empty():
		last_divergence = "reconstruction: %s" % validation
		push_error("[Replay] %s" % last_divergence)
		playback_complete = true
		playback_succeeded = false
		playback_finished.emit(false)
		return
	var replay_camera := level.get_node_or_null("CameraRig") as TacticalCamera
	if replay_camera:
		# Replay pause doubles as an inspection/photo mode. Normal battle cameras
		# retain inherited processing and therefore remain frozen by their pause menu.
		replay_camera.process_mode = Node.PROCESS_MODE_ALWAYS
	_create_controls()
	_play.call_deferred()

func _play() -> void:
	print("[Replay] PLAYBACK — %d actions" % recording.actions.size())
	var tracks_supply := bool(recording.configuration.get("supply_points_enabled", false))
	var tracks_aim := bool(recording.configuration.get("aim_enabled", false))
	var tracks_shield := bool(recording.configuration.get("shield_enabled", false))
	var initial_state := StateFingerprint.capture(level.turn_manager, level.battle_controller.grid_manager, level.objective_manager, tracks_supply, tracks_aim, tracks_shield)
	if recording.schema_version >= 3 and not recording.initial_state_fingerprint.is_empty() and initial_state != recording.initial_state_fingerprint:
		_fail("reconstruction", -1, {}, "initial state fingerprint differs\nExpected: %s\nActual:   %s" % [recording.initial_state_fingerprint, initial_state])
		return
	for index in recording.actions.size():
		last_divergence = ""
		await _wait_until_playing()
		if level.turn_manager.battle_result != TurnManager.BattleResult.ONGOING:
			break
		var record: Dictionary = recording.actions[index]
		var record_issue := ReplayRecordTools.validate_action_record(record, recording.schema_version)
		if not record_issue.is_empty():
			_fail("reconstruction", index, record, record_issue)
			return
		if recording.schema_version >= 3:
			var actual_revision := level.battle_controller.action_service.state_revision
			if int(record.get("base_revision", -1)) != actual_revision:
				_fail("validation", index, record, "base_revision differs: expected %s, got %d" % [record.get("base_revision"), actual_revision])
				return
		var expected_state: String = record.get("expected_state", "")
		var state_before := StateFingerprint.capture(level.turn_manager, level.battle_controller.grid_manager, level.objective_manager, tracks_supply, tracks_aim, tracks_shield)
		# Some gameplay signals commit an automatic action while their enclosing action is
		# still finishing. If the earlier replayed action already produced this exact
		# authoritative state, the nested record has already been applied.
		if recording.schema_version == BattleReplayRecording.LEGACY_SCHEMA_VERSION and record.get("kind", "") != "depart" and not expected_state.is_empty() and state_before == expected_state:
			verified_actions += 1
			playback_progressed.emit(verified_actions, recording.actions.size())
			print("[Replay] COALESCED — action %d (%s) was already applied by gameplay rules" % [index, record.get("kind", "unknown")])
			await _action_interval()
			continue
		await _focus_action(record)
		await _wait_until_playing()
		if not await _execute(record):
			_fail("resolution", index, record, last_divergence if not last_divergence.is_empty() else "authoritative execution rejected the record")
			return
		if recording.schema_version >= 3:
			var committed_revision := level.battle_controller.action_service.state_revision
			if int(record.get("committed_revision", -1)) != committed_revision:
				_fail("commit", index, record, "committed_revision differs: expected %s, got %d" % [record.get("committed_revision"), committed_revision])
				return
		var actual_state := StateFingerprint.capture(level.turn_manager, level.battle_controller.grid_manager, level.objective_manager, tracks_supply, tracks_aim, tracks_shield)
		if not expected_state.is_empty() and actual_state != expected_state:
			_fail("comparison", index, record, "state fingerprint differs\nExpected: %s\nActual:   %s" % [expected_state, actual_state])
			return
		verified_actions += 1
		playback_progressed.emit(verified_actions, recording.actions.size())
		await _action_interval()
	var matches: bool = level.turn_manager.battle_result == recording.expected_result
	print("[Replay] %s — verified %d/%d actions | expected %s, got %s" % [
		"COMPLETED" if matches else "DIVERGED",
		verified_actions, recording.actions.size(),
		TurnManager.BattleResult.keys()[recording.expected_result],
		TurnManager.BattleResult.keys()[level.turn_manager.battle_result],
	])
	playback_complete = true
	playback_succeeded = matches
	playback_finished.emit(matches)

func set_playback_paused(paused: bool) -> void:
	playback_paused = paused
	if paused and is_instance_valid(level):
		var replay_camera := level.get_node_or_null("CameraRig") as TacticalCamera
		if replay_camera:
			replay_camera.clear_cinematic_view()
	get_tree().paused = paused
	print("[Replay] %s at action %d/%d" % ["PAUSED" if paused else "PLAYING", verified_actions, recording.actions.size()])

func set_playback_speed(speed: float) -> void:
	playback_speed = clampf(speed, 0.5, 4.0)
	print("[Replay] SPEED — %.1f×" % playback_speed)

func set_camera_mode(mode: CameraMode) -> void:
	camera_mode = mode
	var replay_camera := level.get_node_or_null("CameraRig") as TacticalCamera if is_instance_valid(level) else null
	if replay_camera and camera_mode != CameraMode.CINEMATIC:
		replay_camera.clear_cinematic_view()

func _wait_until_playing() -> void:
	while playback_paused:
		await get_tree().process_frame

func _action_interval() -> void:
	await _wait_until_playing()
	var delay := action_delay / maxf(playback_speed, 0.1)
	if delay > 0.0:
		await get_tree().create_timer(delay, false).timeout

func _focus_action(record: Dictionary) -> void:
	if record.get("kind", "") == "end_turn":
		return
	var actor := _find_unit(record.get("actor", ""))
	if not is_instance_valid(actor):
		return
	var camera := level.get_node_or_null("CameraRig") as TacticalCamera
	if not camera:
		return
	if camera_mode == CameraMode.FREE:
		camera.clear_cinematic_view()
	elif camera_mode == CameraMode.FOLLOW_ACTION:
		camera.focus_position(actor.global_position)
	elif camera_mode == CameraMode.CINEMATIC:
		var focus_point := _action_focus_point(record, actor)
		var director := level.action_camera_director
		if director:
			await director.present(actor, StringName(record.get("kind", "")), focus_point, actor.stats.current_ap, false, true)

func _action_focus_point(record: Dictionary, actor: TacticalUnit) -> Vector3:
	var kind: String = record.get("kind", "")
	if kind == "move":
		var destination := _array_to_cell(record.get("to", []))
		if destination.x >= 0:
			return level.battle_controller.grid_manager.grid_to_world(destination)
	if kind in ["attack", "rescue"]:
		var target := _find_unit(record.get("target", ""))
		if is_instance_valid(target):
			return target.global_position
	var facing := Vector3.FORWARD
	if is_instance_valid(actor.visual_adapter):
		facing = actor.visual_adapter.global_basis.z.normalized()
	return actor.global_position + facing * 4.0

func _create_controls() -> void:
	var canvas := level.get_node_or_null("Visualizers/BattleUI") as CanvasLayer
	if not canvas:
		return
	_controls = ReplayControlsData.new()
	_controls.name = "ReplayControls"
	canvas.add_child(_controls)
	_controls.setup(self)

func _execute(record: Dictionary) -> bool:
	var kind: String = record.get("kind", "")
	if kind == "depart":
		return level.objective_manager.end_mission_early()
	if kind == "end_turn":
		level.turn_manager.end_current_turn()
		return true
	var actor: TacticalUnit = _find_unit(record.get("actor", ""))
	if not is_instance_valid(actor):
		return false
	# Zero-AP extraction is legal for exhausted/non-active units as well.
	if kind == "extract":
		return await _replay_mission(record, actor)
	if not _activate(actor):
		print("[Replay] ACTOR REJECTED — wanted %s | active %s | phase %s" % [
			actor.name,
			_active_unit_name(),
			TurnManager.TurnPhase.keys()[level.turn_manager.current_phase],
		])
		return false
	match kind:
		"move":
			var request := TacticalActionRequest.from_dictionary(record.get("request", {}))
			request.source = TacticalActionRequest.Source.REPLAY
			if recording.schema_version == BattleReplayRecording.LEGACY_SCHEMA_VERSION: request.expected_revision = level.battle_controller.action_service.state_revision
			var original_movement_speed := actor.movement_speed
			actor.movement_speed = original_movement_speed * playback_speed
			var result := await level.battle_controller.action_service.submit_move(request)
			if is_instance_valid(actor):
				actor.movement_speed = original_movement_speed
			if result == null:
				var rejection := level.battle_controller.action_service.last_rejection
				last_divergence = "move rejected [%s]: %s" % [rejection.code, rejection.message]
				return false
			var identity_difference := _compare_result_identity(result, record)
			if not identity_difference.is_empty(): last_divergence = identity_difference; return false
			var difference := result.compare_resolved(record.get("resolved", {}))
			if not difference.is_empty():
				last_divergence = difference
				return false
			return true
		"attack":
			var request_data: Dictionary = record.get("request", {})
			if request_data.is_empty():
				push_error("Replay attack is missing its versioned request")
				return false
			var request := TacticalActionRequest.from_dictionary(request_data)
			request.source = TacticalActionRequest.Source.REPLAY
			if recording.schema_version == BattleReplayRecording.LEGACY_SCHEMA_VERSION: request.expected_revision = level.battle_controller.action_service.state_revision
			var result := await level.battle_controller.action_service.submit_attack(request)
			if result == null:
				var rejection := level.battle_controller.action_service.last_rejection
				last_divergence = "attack rejected [%s]: %s" % [rejection.code, rejection.message]
				return false
			var identity_difference := _compare_result_identity(result, record)
			if not identity_difference.is_empty(): last_divergence = identity_difference; return false
			var difference := result.compare_resolved(record.get("resolved", {}))
			if not difference.is_empty():
				last_divergence = difference
				return false
			return true
		"reload":
			var request := TacticalActionRequest.from_dictionary(record.get("request", {}))
			request.source = TacticalActionRequest.Source.REPLAY
			var result := await level.battle_controller.action_service.submit_reload(request)
			if result == null:
				var rejection := level.battle_controller.action_service.last_rejection
				last_divergence = "reload rejected [%s]: %s" % [rejection.code, rejection.message]
				return false
			var identity_difference := _compare_result_identity(result, record)
			if not identity_difference.is_empty(): last_divergence = identity_difference; return false
			var difference := result.compare_resolved(record.get("resolved", {}))
			if not difference.is_empty(): last_divergence = difference; return false
			return true
		"aim":
			var request := TacticalActionRequest.from_dictionary(record.get("request", {}))
			request.source = TacticalActionRequest.Source.REPLAY
			var result := await level.battle_controller.action_service.submit_aim(request)
			if result == null:
				var rejection := level.battle_controller.action_service.last_rejection
				last_divergence = "aim rejected [%s]: %s" % [rejection.code, rejection.message]
				return false
			var identity_difference := _compare_result_identity(result, record)
			if not identity_difference.is_empty(): last_divergence = identity_difference; return false
			var difference := result.compare_resolved(record.get("resolved", {}))
			if not difference.is_empty(): last_divergence = difference; return false
			return true
		"shield":
			var request := TacticalActionRequest.from_dictionary(record.get("request", {}))
			request.source = TacticalActionRequest.Source.REPLAY
			var result := await level.battle_controller.action_service.submit_shield(request)
			if result == null:
				var rejection := level.battle_controller.action_service.last_rejection
				last_divergence = "shield rejected [%s]: %s" % [rejection.code, rejection.message]
				return false
			var identity_difference := _compare_result_identity(result, record)
			if not identity_difference.is_empty(): last_divergence = identity_difference; return false
			var difference := result.compare_resolved(record.get("resolved", {}))
			if not difference.is_empty(): last_divergence = difference; return false
			return true
		"defend":
			return await _replay_simple(record)
		"wait":
			return await _replay_simple(record)
		"rescue":
			return await _replay_mission(record, actor)
	return false

func _replay_simple(record: Dictionary) -> bool:
	var request := TacticalActionRequest.from_dictionary(record.get("request", {}))
	request.source = TacticalActionRequest.Source.REPLAY
	if recording.schema_version == BattleReplayRecording.LEGACY_SCHEMA_VERSION: request.expected_revision = level.battle_controller.action_service.state_revision
	var result := await level.battle_controller.action_service.submit_simple(request)
	if result == null:
		var rejection := level.battle_controller.action_service.last_rejection
		last_divergence = "%s rejected [%s]: %s" % [request.kind, rejection.code, rejection.message]
		return false
	var identity_difference := _compare_result_identity(result, record)
	if not identity_difference.is_empty(): last_divergence = identity_difference; return false
	var difference := result.compare_resolved(record.get("resolved", {}))
	if not difference.is_empty():
		last_divergence = difference
		return false
	return true

func _replay_mission(record: Dictionary, actor: TacticalUnit) -> bool:
	var request_data: Dictionary = record.get("request", {})
	# Prototype 1 recordings predate versioned mission requests.
	var request: TacticalActionRequest
	if request_data.is_empty():
		var target := _find_unit(record.get("target", ""))
		request = level.battle_controller.action_service.make_mission_request(StringName(record.get("kind", "")), actor, target, TacticalActionRequest.Source.REPLAY)
	else:
		request = TacticalActionRequest.from_dictionary(request_data)
		request.source = TacticalActionRequest.Source.REPLAY
		if recording.schema_version == BattleReplayRecording.LEGACY_SCHEMA_VERSION: request.expected_revision = level.battle_controller.action_service.state_revision
	var result := await level.battle_controller.action_service.submit_mission(request)
	if result == null:
		var rejection := level.battle_controller.action_service.last_rejection
		last_divergence = "mission action rejected [%s]: %s" % [rejection.code, rejection.message]
		return false
	var identity_difference := _compare_result_identity(result, record)
	if not identity_difference.is_empty(): last_divergence = identity_difference; return false
	var expected: Dictionary = record.get("resolved", {})
	if expected.is_empty(): return true
	var difference := result.compare_resolved(expected)
	if not difference.is_empty():
		last_divergence = difference
		return false
	return true

func _activate(actor: TacticalUnit) -> bool:
	if level.turn_manager.active_unit == actor:
		return true
	if level.turn_manager.current_phase == TurnManager.TurnPhase.PLAYER_TURN:
		return level.turn_manager.select_player_unit(actor)
	return false

func _find_unit(unit_name: String) -> TacticalUnit:
	if unit_name.is_empty(): return null
	if is_instance_valid(level) and is_instance_valid(level.battle_controller.action_service):
		var registered := level.battle_controller.action_service.actor_registry.resolve(StringName(unit_name))
		if is_instance_valid(registered):
			return registered
	var candidate := level.find_child(unit_name, true, false)
	return candidate as TacticalUnit

func _active_unit_name() -> String:
	if is_instance_valid(level.turn_manager.active_unit):
		return String(level.turn_manager.active_unit.name)
	return "none"

func _array_to_cell(value: Variant) -> Vector3i:
	if value is Array and value.size() == 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return Vector3i(-1, -1, -1)

func _compare_result_identity(result, record: Dictionary) -> String:
	if recording.schema_version < 3: return ""
	var expected := {
		"transaction_id": record.get("transaction_id"),
		"base_revision": record.get("base_revision"),
		"committed_revision": record.get("committed_revision"),
	}
	var actual := {
		"transaction_id": result.transaction_id,
		"base_revision": result.base_revision,
		"committed_revision": result.committed_revision,
	}
	return ReplayRecordTools.compare_fields(expected, actual)

func _fail(stage: String, index: int, record: Dictionary, reason: String) -> void:
	var context := ReplayRecordTools.context(index, record) if index >= 0 else "initial battle"
	last_divergence = "%s at %s: %s" % [stage, context, reason]
	push_error("[Replay] %s" % last_divergence)
	playback_complete = true
	playback_succeeded = false
	playback_finished.emit(false)
