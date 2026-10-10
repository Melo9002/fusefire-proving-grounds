class_name AttackQueryResult
extends RefCounted

var validation: ActionValidationResult
var cost := ActionCost.new(1)
var actor_id: StringName
var target_id: StringName
var state_revision: int
var hit_chance := 0
var base_hit_chance := 0
var aim_bonus := 0
var aim_applied := false
var damage_on_hit := 0
var minimum_damage := 0
var maximum_damage := 0
var expected_damage := 0.0
var actor_ap_before := 0
var actor_ap_after := 0
var supply_points_before := 0
var max_supply_points := 0
var supply_points_cost := 1
var supply_points_after := 0
var distance := 0.0
var cover_type := MapCellData.CoverType.NONE
var reason := ""
var aim_point := Vector3.ZERO
var obstruction := "Blocked"
var visibility_fraction := 0.0
var blocking_cell := Vector3i(-1, -1, -1)
var evaluation: CombatRules.AttackEvaluation
var legal_target_ids: Array[StringName] = []
## Targetless actor queries retain every candidate's structured result so UI and
## AI can distinguish tactical legality from their own display/scoring choices.
var candidate_results: Dictionary = {}

func is_legal() -> bool:
	return validation != null and validation.accepted

func has_legal_targets() -> bool:
	return not legal_target_ids.is_empty()

func get_candidate(target: StringName) -> AttackQueryResult:
	return candidate_results.get(target) as AttackQueryResult

