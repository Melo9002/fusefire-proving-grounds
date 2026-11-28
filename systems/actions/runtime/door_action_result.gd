class_name DoorActionResult
extends RefCounted
## The committed result of opening or closing a door: the state change, what it cost (nothing), the geometry it produced (a signature, so a replay can verify the map is the same), and any Guard reactions the
## opening created.

const SCHEMA_VERSION := 1

var transaction_id: int
var base_revision: int
var committed_revision: int
var request: TacticalActionRequest
var door_id: StringName
var state_before: StringName
var state_after: StringName
var actor_cell := Vector3i.ZERO
var actor_ap_before := 0
var actor_ap_after := 0
var geometry_signature := ""
var region: Array[Vector3i] = []
var reaction_events: Array[OverwatchReactionEvent] = []
## Watchers that were eligible but did not fire, with the reason (held fire, still obstructed, shot already legal).
var guard_checks: Dictionary = {}
var combat_rng_state_after := 0
var presentation_suppressed := false
var presentation_completed := false
var presentation_error := ""


func to_replay_record() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "kind": String(request.kind), "actor": String(request.actor_id), "target": String(door_id), "transaction_id": transaction_id, "base_revision": base_revision, "committed_revision": committed_revision, "request": request.to_dictionary(), "resolved": resolved_dictionary()}


func resolved_dictionary() -> Dictionary:
	var reactions: Array = []
	for event in reaction_events:
		reactions.append(event.to_dictionary())
	return {
		"door_id": String(door_id), "state_before": String(state_before), "state_after": String(state_after),
		"actor_ap_before": actor_ap_before, "actor_ap_after": actor_ap_after,
		"geometry_signature": geometry_signature, "combat_rng_state_after": str(combat_rng_state_after),
		"reaction_events": reactions,
	}


func compare_resolved(expected: Dictionary) -> String:
	return ReplayRecordTools.compare_fields(expected, resolved_dictionary(), "resolved")
