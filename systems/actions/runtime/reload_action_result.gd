class_name ReloadActionResult
extends RefCounted

const SCHEMA_VERSION := 3

var transaction_id: int
var base_revision: int
var committed_revision: int
var request: TacticalActionRequest
var cost := ActionCost.new(1)
var actor_ap_before := 0
var actor_ap_after := 0
var supply_points_before := 0
var max_supply_points := 0
var supply_points_after := 0
var supply_points_restored := 0
var presentation_suppressed := false
var presentation_completed := false
var presentation_error := ""

func to_replay_record() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"kind": "reload",
		"actor": String(request.actor_id),
		"transaction_id": transaction_id,
		"base_revision": base_revision,
		"committed_revision": committed_revision,
		"request": request.to_dictionary(),
		"resolved": resolved_dictionary(),
	}

func resolved_dictionary() -> Dictionary:
	return {
		"actor_ap_before": actor_ap_before,
		"actor_ap_after": actor_ap_after,
		"supply_points_before": supply_points_before,
		"max_supply_points": max_supply_points,
		"supply_points_after": supply_points_after,
		"supply_points_restored": supply_points_restored,
	}

func compare_resolved(expected: Dictionary) -> String:
	return ReplayRecordTools.compare_fields(expected, resolved_dictionary(), "resolved")
