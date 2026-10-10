class_name ShieldActionResult
extends RefCounted

const SCHEMA_VERSION := 5

var transaction_id := 0
var base_revision := 0
var committed_revision := 0
var request: TacticalActionRequest
var cost := ActionCost.new(1)
var actor_ap_before := 0
var actor_ap_after := 0
var aiming_before := false
var aiming_after := false
var shielding_before := false
var shielding_after := false
var facing := Vector2.ZERO
var protected_arc_degrees := 0.0
var accuracy_modifier := 0
var damage_multiplier := 1.0
var presentation_suppressed := false
var presentation_completed := false
var presentation_error := ""

func to_replay_record() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION, "kind": "shield", "actor": String(request.actor_id),
		"target": String(request.target_id), "transaction_id": transaction_id,
		"base_revision": base_revision, "committed_revision": committed_revision,
		"request": request.to_dictionary(), "resolved": resolved_dictionary(),
	}

func resolved_dictionary() -> Dictionary:
	return {
		"actor_ap_before": actor_ap_before, "actor_ap_after": actor_ap_after,
		"aiming_before": aiming_before, "aiming_after": aiming_after,
		"shielding_before": shielding_before, "shielding_after": shielding_after,
		"facing_milli": [roundi(facing.x * 1000.0), roundi(facing.y * 1000.0)],
		"protected_arc_milli": roundi(protected_arc_degrees * 1000.0),
		"accuracy_modifier": accuracy_modifier,
		"damage_multiplier_milli": roundi(damage_multiplier * 1000.0),
	}

func compare_resolved(expected: Dictionary) -> String:
	return ReplayRecordTools.compare_fields(expected, resolved_dictionary(), "resolved")
