class_name ShieldQueryResult
extends RefCounted

var actor_id: StringName
var threat_id: StringName
var state_revision := 0
var validation: ActionValidationResult
var cost := ActionCost.new(1)
var actor_ap_before := 0
var actor_ap_after := 0
var facing := Vector2.ZERO
var protected_arc_degrees := 0.0
var accuracy_modifier := 0
var damage_multiplier := 1.0
var legal_threat_ids: Array[StringName] = []
var candidate_results: Dictionary = {}

func is_legal() -> bool:
	return validation != null and validation.accepted

func reason() -> String:
	return validation.message if validation != null else "Shield Stance availability was not evaluated"

func has_legal_threats() -> bool:
	return not legal_threat_ids.is_empty()
