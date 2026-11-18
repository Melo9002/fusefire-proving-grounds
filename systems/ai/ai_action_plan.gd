class_name AIActionPlan
extends RefCounted
## One short plan a unit could carry out with the AP and supply it has: its steps, what it costs and
## what it is worth. Plain data built by AIPlanEvaluator from the shared queries and combat rules;
## it never executes anything and never draws a random number.

const MOVE := &"move"
const AIM := &"aim"
const RELOAD := &"reload"
const ATTACK := &"attack"
const SHIELD := &"shield"

var steps: Array[StringName] = []
var target_id := &""
## Where a Move step ends; (-1, -1, -1) when the plan has no move.
var destination := Vector3i(-1, -1, -1)
var shots := 0
var ap_cost := 0
var supply_cost := 0
## HP-capped expected damage plus kill value over the whole sequence (AITargetScorer.shot_sequence_value).
var value := 0.0
## What the plan costs in exposure or danger (a Move's destination); zero for plans that stay put.
var risk := 0.0
var summary := ""

func net_value() -> float:
	return value - risk

func has_move() -> bool:
	return MOVE in steps

func first_step() -> StringName:
	return steps[0] if not steps.is_empty() else &""

## Whether the unit can pay for this plan right now.
func is_affordable(available_ap: int, available_supply: int, uses_supply: bool) -> bool:
	return ap_cost <= available_ap and (not uses_supply or supply_cost <= available_supply)

func to_dictionary() -> Dictionary:
	return {
		"steps": steps.map(func(step: StringName) -> String: return String(step)),
		"target": String(target_id),
		"destination": destination,
		"shots": shots,
		"ap_cost": ap_cost,
		"supply_cost": supply_cost,
		"value": value,
		"risk": risk,
		"summary": summary,
	}
