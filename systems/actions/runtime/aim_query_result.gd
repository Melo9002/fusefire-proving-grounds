class_name AimQueryResult
extends RefCounted

var actor_id: StringName
var state_revision := 0
var validation: ActionValidationResult
var cost := ActionCost.new(1)
var actor_ap_before := 0
var actor_ap_after := 0
var aiming_before := false
var accuracy_bonus := TacticalState.AIM_ACCURACY_BONUS

func is_legal() -> bool:
	return validation != null and validation.accepted

func reason() -> String:
	return validation.message if validation != null else "Aim availability was not evaluated"
