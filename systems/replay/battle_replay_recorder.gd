class_name BattleReplayRecorder
extends RefCounted

const RecordingData := preload("res://systems/replay/battle_replay_recording.gd")
const ReplaySession := preload("res://systems/replay/battle_replay_session.gd")
const StateFingerprint := preload("res://systems/replay/battle_state_fingerprint.gd")

var recording = RecordingData.new()
var _battle_controller: BattleController
var _turn_manager: TurnManager
var _objective_manager: ObjectiveManager

func begin(configuration: Dictionary, battle_controller: BattleController, turn_manager: TurnManager, objective_manager: ObjectiveManager = null) -> void:
	recording.configuration = configuration.duplicate(true)
	_battle_controller = battle_controller
	_turn_manager = turn_manager
	_objective_manager = objective_manager
	battle_controller.replay_action_committed.connect(_on_action_committed)
	turn_manager.turn_ended.connect(_on_action_committed)
	turn_manager.battle_ended.connect(_on_battle_ended)

func _on_action_committed(record: Dictionary) -> void:
	var recorded := record.duplicate(true)
	recorded["expected_state"] = StateFingerprint.capture(_turn_manager, _battle_controller.grid_manager, _objective_manager)
	recording.append_action(recorded)

func _on_battle_ended(result: TurnManager.BattleResult) -> void:
	recording.expected_result = result
	ReplaySession.store(recording)
	print("[Replay] RECORDED — %d actions | %s" % [recording.actions.size(), TurnManager.BattleResult.keys()[result]])
