class_name SimpleActionResult
extends RefCounted

const SCHEMA_VERSION := 2
var transaction_id: int
var base_revision: int
var committed_revision: int
var request: TacticalActionRequest
var actor_ap_before: int
var actor_ap_after: int
var defending_before := false
var defending_after := false
var presentation_suppressed := false
var presentation_completed := false
var presentation_error := ""

func to_replay_record() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "kind": String(request.kind), "actor": String(request.actor_id), "transaction_id": transaction_id, "base_revision": base_revision, "committed_revision": committed_revision, "request": request.to_dictionary(), "resolved": resolved_dictionary()}

func resolved_dictionary() -> Dictionary:
	return {"actor_ap_before": actor_ap_before, "actor_ap_after": actor_ap_after, "defending_before": defending_before, "defending_after": defending_after}

func compare_resolved(expected: Dictionary) -> String:
	return ReplayRecordTools.compare_fields(expected, resolved_dictionary(), "resolved")
