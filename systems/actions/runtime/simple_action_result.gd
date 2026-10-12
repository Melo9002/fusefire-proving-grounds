class_name SimpleActionResult
extends RefCounted

const SCHEMA_VERSION := 9
var transaction_id: int
var base_revision: int
var committed_revision: int
var request: TacticalActionRequest
var actor_ap_before: int
var actor_ap_after: int
var defending_before := false
var defending_after := false
var condition_id: StringName
var condition_removed := false
var charges_before := 0
var charges_after := 0
var presentation_suppressed := false
var presentation_completed := false
var presentation_error := ""

func to_replay_record() -> Dictionary:
	var payload_version := SCHEMA_VERSION if request.kind == &"emergency_seal" else 2
	return {"schema_version": payload_version, "kind": String(request.kind), "actor": String(request.actor_id), "transaction_id": transaction_id, "base_revision": base_revision, "committed_revision": committed_revision, "request": request.to_dictionary(), "resolved": resolved_dictionary()}

func resolved_dictionary() -> Dictionary:
	return {"actor_ap_before": actor_ap_before, "actor_ap_after": actor_ap_after, "defending_before": defending_before, "defending_after": defending_after, "condition_id": String(condition_id), "condition_removed": condition_removed, "charges_before": charges_before, "charges_after": charges_after}

func compare_resolved(expected: Dictionary) -> String:
	return ReplayRecordTools.compare_fields(expected, resolved_dictionary(), "resolved")
