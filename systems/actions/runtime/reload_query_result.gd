class_name ReloadQueryResult
extends RefCounted

var actor_id: StringName
var state_revision: int
var validation: ActionValidationResult
var cost := ActionCost.new(1)
var actor_ap_before := 0
var actor_ap_after := 0
var supply_points_before := 0
var max_supply_points := 0
var supply_points_after := 0
var supply_points_restored := 0

func is_legal() -> bool:
	return validation != null and validation.accepted

func reason() -> String:
	return validation.message if validation != null else "Reload availability was not evaluated"
