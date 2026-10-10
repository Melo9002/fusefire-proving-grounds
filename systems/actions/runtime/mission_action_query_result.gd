class_name MissionActionQueryResult
extends RefCounted

var kind: StringName
var actor_id: StringName
var target_id: StringName
var validation: ActionValidationResult
var cost := ActionCost.new()
var state_revision: int
var legal_target_ids: Array[StringName] = []
var candidate_results: Dictionary[StringName, MissionActionQueryResult] = {}

func is_legal() -> bool:
	return validation != null and validation.accepted

func reason() -> String:
	return validation.message if validation != null else "Action availability was not evaluated"

func get_candidate(candidate_id: StringName) -> MissionActionQueryResult:
	return candidate_results.get(candidate_id)
