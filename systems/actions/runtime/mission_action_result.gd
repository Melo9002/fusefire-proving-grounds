class_name MissionActionResult
extends RefCounted

const SCHEMA_VERSION := 2

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

func to_replay_record() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "kind": String(request.kind), "actor": String(request.actor_id), "target": String(request.target_id), "transaction_id": transaction_id, "request": request.to_dictionary(), "resolved": resolved_dictionary()}

func resolved_dictionary() -> Dictionary:
	return {"objective_state": objective_state_after.duplicate(true), "mission_counters": mission_counters_after.duplicate(true), "actor_removed_from_roster": actor_removed_from_roster}

func compare_resolved(expected: Dictionary) -> String:
	var actual := resolved_dictionary()
	for key in actual:
		if not expected.has(key): return "missing resolved field '%s'" % key
		if expected[key] != actual[key]: return "resolved field '%s' differs: expected %s, got %s" % [key, expected[key], actual[key]]
	return ""
