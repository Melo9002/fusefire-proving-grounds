class_name MoveActionResult
extends RefCounted

const SCHEMA_VERSION := 2
var transaction_id: int
var base_revision: int
var committed_revision: int
var request: TacticalActionRequest
var cost := ActionCost.new(1)
var start_cell: Vector3i
var target_cell: Vector3i
var actor_ap_before: int
var actor_ap_after: int
var presentation_path := PackedVector3Array()
var visual_segments: Array[StringName] = []
var presentation_suppressed := false
var presentation_completed := false

func to_replay_record() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "kind": "move", "actor": String(request.actor_id), "transaction_id": transaction_id, "request": request.to_dictionary(), "resolved": resolved_dictionary()}

func resolved_dictionary() -> Dictionary:
	return {"from": [start_cell.x, start_cell.y, start_cell.z], "to": [target_cell.x, target_cell.y, target_cell.z], "actor_ap_before": actor_ap_before, "actor_ap_after": actor_ap_after}

func compare_resolved(expected: Dictionary) -> String:
	var actual := resolved_dictionary()
	for key in actual:
		if not expected.has(key): return "missing resolved field '%s'" % key
		if expected[key] != actual[key]: return "resolved field '%s' differs: expected %s, got %s" % [key, expected[key], actual[key]]
	return ""
