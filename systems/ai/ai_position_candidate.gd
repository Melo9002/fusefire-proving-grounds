class_name AIPositionCandidate
extends RefCounted
## One movement option the AI considered, as published in decision traces and F3.
## to_dictionary() reproduces the established trace keys exactly, so overlays, the
## simulator's JSON and replay-adjacent tooling read the same shape as before.

const CONSIDERED := "considered"
const REJECTED := "rejected"

var cell := Vector3i(-1, -1, -1)
var status := CONSIDERED
## NAN until scored; options rejected before scoring have no score.
var score := NAN
var summary := ""
var reason := ""
## Optional score components (progress, cover, exposure, firing, danger, squad).
var components: Dictionary = {}
var chosen := false
var _chosen_assigned := false

static func considered(candidate_cell: Vector3i, candidate_score: float, candidate_summary: String, score_components: Dictionary = {}) -> AIPositionCandidate:
	var result := AIPositionCandidate.new()
	result.cell = candidate_cell
	result.score = candidate_score
	result.summary = candidate_summary
	result.components = score_components
	return result

static func rejected_before_scoring(candidate_cell: Vector3i, rejection_reason: String) -> AIPositionCandidate:
	var result := AIPositionCandidate.new()
	result.cell = candidate_cell
	result.status = REJECTED
	result.reason = rejection_reason
	return result

func reject(rejection_reason: String) -> void:
	status = REJECTED
	reason = rejection_reason

func is_rejected() -> bool:
	return status == REJECTED

## Marks the final selection. Left unassigned, the key is absent from the trace.
func mark_chosen(is_chosen: bool) -> void:
	chosen = is_chosen
	_chosen_assigned = true

func to_dictionary() -> Dictionary:
	var record := {"cell": cell}
	if not is_nan(score): record["score"] = score
	record["status"] = status
	if not summary.is_empty(): record["summary"] = summary
	record.merge(components)
	if not reason.is_empty(): record["reason"] = reason
	if _chosen_assigned: record["chosen"] = chosen
	return record
