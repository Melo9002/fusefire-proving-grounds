class_name AimActionResult
extends RefCounted

const SCHEMA_VERSION := 4

var transaction_id := 0
var base_revision := 0
var committed_revision := 0
var request: TacticalActionRequest
var cost := ActionCost.new(1)
var actor_ap_before := 0
var actor_ap_after := 0
var aiming_before := false
var aiming_after := false
var accuracy_bonus := TacticalState.AIM_ACCURACY_BONUS
var presentation_suppressed := false
var presentation_completed := false
var presentation_error := ""

func to_replay_record() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION, "kind": "aim", "actor": String(request.actor_id),
		"transaction_id": transaction_id, "base_revision": base_revision,
		"committed_revision": committed_revision, "request": request.to_dictionary(),
		"resolved": resolved_dictionary(),
	}

func resolved_dictionary() -> Dictionary:
	return {
		"actor_ap_before": actor_ap_before, "actor_ap_after": actor_ap_after,
		"aiming_before": aiming_before, "aiming_after": aiming_after,
		"accuracy_bonus": accuracy_bonus,
	}

func compare_resolved(expected: Dictionary) -> String:
	return ReplayRecordTools.compare_fields(expected, resolved_dictionary(), "resolved")
