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
var objective_state_before: Dictionary = {}
var objective_state_after: Dictionary = {}
var carried_actor_id: StringName = &""
var presentation_path := PackedVector3Array()
var visual_segments: Array[StringName] = []
var presentation_suppressed := false
var presentation_completed := false
var presentation_error := ""

func to_replay_record() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "kind": "move", "actor": String(request.actor_id), "transaction_id": transaction_id, "base_revision": base_revision, "committed_revision": committed_revision, "request": request.to_dictionary(), "resolved": resolved_dictionary()}

func resolved_dictionary() -> Dictionary:
	return {"from": [start_cell.x, start_cell.y, start_cell.z], "to": [target_cell.x, target_cell.y, target_cell.z], "actor_ap_before": actor_ap_before, "actor_ap_after": actor_ap_after, "objective_state": objective_state_after.duplicate(true), "carried_actor_id": String(carried_actor_id)}

func compare_resolved(expected: Dictionary) -> String:
	return ReplayRecordTools.compare_fields(expected, resolved_dictionary(), "resolved")
