class_name AITargetCandidate
extends RefCounted
## One hostile the AI considered shooting, as published in decision traces and F3.
## to_dictionary() reproduces the established trace keys exactly.

const CONSIDERED := "considered"
const REJECTED := "rejected"

var target := ""
var cell := Vector3i(-1, -1, -1)
var status := CONSIDERED
var score := NAN
var summary := ""
var hit_chance := 0
var expected_damage := 0.0
## Score components (vulnerability, focus, vip, threat, mission, focus_count, damage_value, damage_on_hit).
var components: Dictionary = {}
## Why an option was rejected, with the shared query's validation code.
var reason := ""
var code := ""
var chosen := false
var _chosen_assigned := false

static func considered(target_name: String, target_cell: Vector3i, target_score: float, score_summary: String,
		chance: int, expected: float, score_components: Dictionary) -> AITargetCandidate:
	var result := AITargetCandidate.new()
	result.target = target_name
	result.cell = target_cell
	result.score = target_score
	result.summary = score_summary
	result.hit_chance = chance
	result.expected_damage = expected
	result.components = score_components
	return result

static func rejected(target_name: String, target_cell: Vector3i, rejection_reason: String, validation_code: String) -> AITargetCandidate:
	var result := AITargetCandidate.new()
	result.target = target_name
	result.cell = target_cell
	result.status = REJECTED
	result.reason = rejection_reason
	result.code = validation_code
	return result

func is_rejected() -> bool:
	return status == REJECTED

func mark_chosen(is_chosen: bool) -> void:
	chosen = is_chosen
	_chosen_assigned = true

func to_dictionary() -> Dictionary:
	var record := {"target": target, "cell": cell}
	if is_rejected():
		record["status"] = status
		record["reason"] = reason
		record["code"] = code
	else:
		record["score"] = score
		record["status"] = status
		record["summary"] = summary
		record["hit_chance"] = hit_chance
		record["expected_damage"] = expected_damage
		record.merge(components)
	if _chosen_assigned: record["chosen"] = chosen
	return record
