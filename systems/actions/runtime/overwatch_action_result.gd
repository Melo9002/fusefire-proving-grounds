class_name OverwatchActionResult
extends RefCounted

const SCHEMA_VERSION := 6

var transaction_id := 0
var base_revision := 0
var committed_revision := 0
var request: TacticalActionRequest
var cost := ActionCost.new(0, true, true)
var actor_ap_before := 0
var actor_ap_after := 0
var supply_points_before := 0
var overwatching_before := false
var overwatching_after := false
var presentation_suppressed := false
var presentation_completed := false
var presentation_error := ""

func to_replay_record() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION, "kind": "overwatch", "actor": String(request.actor_id),
		"transaction_id": transaction_id, "base_revision": base_revision,
		"committed_revision": committed_revision, "request": request.to_dictionary(),
		"resolved": resolved_dictionary(),
	}

func resolved_dictionary() -> Dictionary:
	return {
		"actor_ap_before": actor_ap_before, "actor_ap_after": actor_ap_after,
		"supply_points_before": supply_points_before,
		"overwatching_before": overwatching_before, "overwatching_after": overwatching_after,
	}

func compare_resolved(expected: Dictionary) -> String:
	return ReplayRecordTools.compare_fields(expected, resolved_dictionary(), "resolved")
