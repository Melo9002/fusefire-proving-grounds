class_name OverwatchQueryResult
extends RefCounted

var actor_id: StringName
var state_revision := 0
var validation: ActionValidationResult
var cost := ActionCost.new(0, true, true)
var actor_ap_before := 0
var actor_ap_after := 0
var supply_points_before := 0
var required_supply_points := 1
var overwatching_before := false

func is_legal() -> bool:
	return validation != null and validation.accepted

func reason() -> String:
	return validation.message if validation != null else "Overwatch availability was not evaluated"
