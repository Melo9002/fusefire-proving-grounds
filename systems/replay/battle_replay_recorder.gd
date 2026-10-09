class_name BattleReplayRecorder
extends RefCounted

const RecordingData := preload("res://systems/replay/battle_replay_recording.gd")
const ReplaySession := preload("res://systems/replay/battle_replay_session.gd")
const StateFingerprint := preload("res://systems/replay/battle_state_fingerprint.gd")

var recording = RecordingData.new()
var _battle_controller: BattleController
var _turn_manager: TurnManager
var _objective_manager: ObjectiveManager
var _finalization_scheduled := false
var _finalized := false

func begin(configuration: Dictionary, battle_controller: BattleController, turn_manager: TurnManager, objective_manager: ObjectiveManager = null) -> void:
	recording.configuration = configuration.duplicate(true)
	_battle_controller = battle_controller
	_turn_manager = turn_manager
	_objective_manager = objective_manager
	recording.initial_state_fingerprint = StateFingerprint.capture(_turn_manager, _battle_controller.grid_manager, _objective_manager)
	battle_controller.replay_action_committed.connect(_on_action_committed)
	if is_instance_valid(battle_controller.action_service):
		battle_controller.action_service.action_committed.connect(_on_tactical_action_committed)
	turn_manager.turn_ended.connect(_on_action_committed)
	turn_manager.battle_ended.connect(_on_battle_ended)

func _on_action_committed(record: Dictionary) -> void:
	var recorded := record.duplicate(true)
	recorded["record_index"] = recording.actions.size()
	if not recorded.has("schema_version"):
		recorded["schema_version"] = 1
	if not recorded.has("transaction_id"):
		recorded["transaction_id"] = "command-%06d" % recording.actions.size()
	if not recorded.has("committed_revision") and is_instance_valid(_battle_controller.action_service):
		recorded["committed_revision"] = _battle_controller.action_service.state_revision
		recorded["base_revision"] = maxi(0, int(recorded["committed_revision"]) - 1)
	recorded["expected_state"] = StateFingerprint.capture(_turn_manager, _battle_controller.grid_manager, _objective_manager)
	recording.append_action(recorded)

func _on_tactical_action_committed(result) -> void:
	_on_action_committed(result.to_replay_record())

func _on_battle_ended(result: TurnManager.BattleResult) -> void:
	recording.expected_result = result
	# Publish the live recording immediately because battle-end UI and tests query
	# the session from the battle_ended signal. A lethal action's committed signal
	# follows later in the same synchronous call stack and appends to this object.
	ReplaySession.store(recording)
	if _finalization_scheduled or _finalized:
		return
	_finalization_scheduled = true
	_finalize_recording.call_deferred()

func _finalize_recording() -> void:
	if _finalized:
		return
	_finalization_scheduled = false
	_finalized = true
	print("[Replay] RECORDED — %d actions | %s" % [recording.actions.size(), TurnManager.BattleResult.keys()[recording.expected_result]])
