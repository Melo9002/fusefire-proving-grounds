class_name MissionActionResult
extends RefCounted

const SCHEMA_VERSION := 2
const TERMINAL_SCHEMA_VERSION := 8

var transaction_id: int
var base_revision: int
var committed_revision: int
var request: TacticalActionRequest
var actor_position := Vector3.ZERO
var target_position := Vector3.ZERO
var objective_state_before: Dictionary = {}
var objective_state_after: Dictionary = {}
var mission_counters_before: Dictionary = {}
var mission_counters_after: Dictionary = {}
var actor_removed_from_roster := false
var presentation_suppressed := false
var presentation_completed := false
var presentation_error := ""
var actor_ap_before := 0
var actor_ap_after := 0
var terminal_position := Vector3i(-1, -1, -1)
var terminal_activated_before := false
var terminal_activated_after := false

func to_replay_record() -> Dictionary:
	var schema := TERMINAL_SCHEMA_VERSION if request.kind == &"interact_terminal" else SCHEMA_VERSION
	return {"schema_version": schema, "kind": String(request.kind), "actor": String(request.actor_id), "target": String(request.target_id), "transaction_id": transaction_id, "base_revision": base_revision, "committed_revision": committed_revision, "request": request.to_dictionary(), "resolved": resolved_dictionary()}

func resolved_dictionary() -> Dictionary:
	var resolved := {"objective_state": objective_state_after.duplicate(true), "mission_counters": mission_counters_after.duplicate(true), "actor_removed_from_roster": actor_removed_from_roster}
	if request.kind == &"interact_terminal":
		resolved.merge({
			"actor_ap_before": actor_ap_before,
			"actor_ap_after": actor_ap_after,
			"terminal_position": [terminal_position.x, terminal_position.y, terminal_position.z],
			"terminal_activated_before": terminal_activated_before,
			"terminal_activated_after": terminal_activated_after,
		}, true)
	return resolved

func compare_resolved(expected: Dictionary) -> String:
	return ReplayRecordTools.compare_fields(expected, resolved_dictionary(), "resolved")
