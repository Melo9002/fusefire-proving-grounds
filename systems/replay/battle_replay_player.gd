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

func begin(p_level: BattleLevel, p_recording) -> void:
	level = p_level
	recording = p_recording
	_create_controls()
	_play.call_deferred()

func _play() -> void:
	print("[Replay] PLAYBACK — %d actions" % recording.actions.size())
	for index in recording.actions.size():
		await _wait_until_playing()
		if level.turn_manager.battle_result != TurnManager.BattleResult.ONGOING:
			break
		var record: Dictionary = recording.actions[index]
		var expected_state: String = record.get("expected_state", "")
		var state_before := StateFingerprint.capture(level.turn_manager, level.battle_controller.grid_manager, level.objective_manager)
		if record.get("kind", "") == "depart" and not expected_state.is_empty() and state_before != expected_state:
			push_error("Replay departure state diverged")
			playback_complete = true
			playback_finished.emit(false)
			return
		# Some gameplay signals commit an automatic action while their enclosing action is
		# still finishing. If the earlier replayed action already produced this exact
		# authoritative state, the nested record has already been applied.
		if record.get("kind", "") != "depart" and not expected_state.is_empty() and state_before == expected_state:
			verified_actions += 1
			playback_progressed.emit(verified_actions, recording.actions.size())
			print("[Replay] COALESCED — action %d (%s) was already applied by gameplay rules" % [index, record.get("kind", "unknown")])
			await _action_interval()
			continue
		await _focus_action(record)
		await _wait_until_playing()
		if not await _execute(record):
			push_error("Replay diverged at action %d: %s" % [index, record])
			playback_complete = true
			playback_finished.emit(false)
			return
		var actual_state := StateFingerprint.capture(level.turn_manager, level.battle_controller.grid_manager, level.objective_manager)
		if record.get("kind", "") != "depart" and not expected_state.is_empty() and actual_state != expected_state:
			push_error("Replay state diverged at action %d (%s by %s).\nExpected: %s\nActual:   %s" % [index, record.get("kind", "unknown"), record.get("actor", ""), expected_state, actual_state])
			playback_complete = true
			playback_finished.emit(false)
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
		await get_tree().create_timer(delay).timeout

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
		return await level.objective_manager.try_extract(actor)
	if not _activate(actor):
		print("[Replay] ACTOR REJECTED — wanted %s | active %s | phase %s" % [
			actor.name,
			_active_unit_name(),
			TurnManager.TurnPhase.keys()[level.turn_manager.current_phase],
		])
		return false
	match kind:
		"move":
			var destination := _array_to_cell(record.get("to", []))
			var original_movement_speed := actor.movement_speed
			actor.movement_speed = original_movement_speed * playback_speed
			var moved := await level.battle_controller.try_move(actor, destination)
			if is_instance_valid(actor):
				actor.movement_speed = original_movement_speed
			if not moved:
				print("[Replay] MOVE REJECTED — actor %s at %s | destination %s | active %s | phase %s | AP %d" % [
					actor.name, level.battle_controller.grid_manager.get_unit_grid(actor), destination,
					_active_unit_name(),
					TurnManager.TurnPhase.keys()[level.turn_manager.current_phase], actor.stats.current_ap,
				])
			return moved
		"attack":
			var target: TacticalUnit = _find_unit(record.get("target", ""))
			if not is_instance_valid(target):
				return false
			return await level.battle_controller.try_attack(actor, target)
		"defend":
			return await level.battle_controller.try_defend(actor)
		"rescue":
			var target: TacticalUnit = _find_unit(record.get("target", ""))
			return is_instance_valid(target) and await level.objective_manager.try_rescue(actor, target)
		"extract":
			return await level.objective_manager.try_extract(actor)
	return false

func _activate(actor: TacticalUnit) -> bool:
	if level.turn_manager.active_unit == actor:
		return true
	if level.turn_manager.current_phase == TurnManager.TurnPhase.PLAYER_TURN:
		return level.turn_manager.select_player_unit(actor)
	return false

func _find_unit(unit_name: String) -> TacticalUnit:
	if unit_name.is_empty(): return null
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
