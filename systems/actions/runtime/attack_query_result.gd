class_name AttackQueryResult
extends RefCounted

var validation: ActionValidationResult
var cost := ActionCost.new(1)
var actor_id: StringName
var target_id: StringName
var state_revision: int
var hit_chance := 0
var cover_type := MapCellData.CoverType.NONE
var reason := ""
var aim_point := Vector3.ZERO
var obstruction := "Blocked"
var evaluation: CombatRules.AttackEvaluation
var legal_target_ids: Array[StringName] = []

func is_legal() -> bool:
	return validation != null and validation.accepted

