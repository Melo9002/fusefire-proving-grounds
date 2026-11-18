class_name AIDecisionContext
extends RefCounted
## What the AI knew and how it was weighing things when a decision was recorded.
## Plain data; the controller fills it and to_dictionary() keeps the established trace keys.

var commander_composition: Dictionary = {}
var attack_plan: Dictionary = {}
var grid_position := Vector3i(-1, -1, -1)
var remaining_ap := -1
var recent_move_origins: Array = []
var consecutive_low_value_actions := 0
## null while a score has not been computed this activation.
var hold_score: Variant = null
var move_acceptance_threshold: Variant = null
var urgency_bonus := 0.0
var route_corridor: Variant = 0

func to_dictionary() -> Dictionary:
	return {
		"commander_composition": commander_composition,
		"attack_plan": attack_plan,
		"grid_position": grid_position,
		"remaining_ap": remaining_ap,
		"recent_move_origins": recent_move_origins,
		"consecutive_low_value_actions": consecutive_low_value_actions,
		"hold_score": hold_score,
		"move_acceptance_threshold": move_acceptance_threshold,
		"urgency_bonus": urgency_bonus,
		"route_corridor": route_corridor,
	}
