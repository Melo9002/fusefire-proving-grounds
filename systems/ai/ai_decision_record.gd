class_name AIDecisionRecord
extends RefCounted
## One AI decision as explained to F3 and the simulator. The controller fills the
## decision facts; BattleController adds the fields it owns (decision id, state
## revision, difficulty, commander) when it publishes. to_dictionary() reproduces the
## established trace keys, so consumers of ai_decision_recorded see the same shape.

## Published as soon as a destination is chosen, so the heatmap appears with the first
## movement frame. Everything else is an explanation of what already happened.
const STAGE_SELECTED := "selected"
const STAGE_EXPLANATION := "explanation"

var actor := "Unknown"
var actor_id := ""
var faction := ""
var expected_action: StringName
var committed_action: StringName
var linked_outcome := {}
var squad_at_decision := {}
var decision_id := 0
var state_revision := 0
var stage := STAGE_EXPLANATION
var action := ""
var subject := ""
var reason := ""
var alternatives := ""
var mission_goal := "None"
var squad_adjustments := "None"
var position_scores := "None"
## Which movement profile layers shaped the position scores, and why ("None" for decisions without movement).
var movement_profile := "None"
var target_scores := "None"
var position_candidates: Array[AIPositionCandidate] = []
var target_candidates: Array[AITargetCandidate] = []
var difficulty := ""
var commander_policy := ""
var commander_policy_id := ""
var strategic_intent := ""
var has_commander := false
var context := AIDecisionContext.new()

func is_selected_move() -> bool:
	return stage == STAGE_SELECTED and action == "Move"

func to_dictionary() -> Dictionary:
	var record := {
		"actor": actor,
		"decision_id": decision_id,
		"state_revision": state_revision,
		"stage": stage,
		"action": action,
		"subject": subject,
		"reason": reason,
		"alternatives": alternatives,
		"mission_goal": mission_goal,
		"squad_adjustments": squad_adjustments,
		"position_scores": position_scores,
		"movement_profile": movement_profile,
		"target_scores": target_scores,
		"position_candidates": position_candidates.map(func(candidate: AIPositionCandidate) -> Dictionary: return candidate.to_dictionary()),
		"target_candidates": target_candidates.map(func(candidate: AITargetCandidate) -> Dictionary: return candidate.to_dictionary()),
		"difficulty": difficulty,
	}
	if has_commander:
		record["actor_id"] = actor_id
		record["faction"] = faction
		record["commander_policy"] = commander_policy
		record["commander_policy_id"] = commander_policy_id
		record["strategic_intent"] = strategic_intent
	if not linked_outcome.is_empty():
		record["linked_outcome"] = linked_outcome
	if not squad_at_decision.is_empty():
		record["squad_at_decision"] = squad_at_decision
	record.merge(context.to_dictionary(), true)
	return record
