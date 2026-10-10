class_name SimpleActionQueryResult
extends RefCounted

var kind: StringName
var actor_id: StringName
var validation: ActionValidationResult
var cost := ActionCost.new()
var actor_ap_before: int
var actor_ap_after: int
var state_revision: int

func is_legal() -> bool:
	return validation != null and validation.accepted

func reason() -> String:
	return validation.message if validation != null else "Action availability was not evaluated"
