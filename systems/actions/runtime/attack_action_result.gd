class_name AttackActionResult
extends RefCounted

const SCHEMA_VERSION := 2

var transaction_id: int
var base_revision: int
var committed_revision: int
var request: TacticalActionRequest
var cost := ActionCost.new(1)
var hit_chance: int
var roll: float
var did_hit: bool
var damage: int
var actor_ap_before: int
var actor_ap_after: int
var target_hp_before: int
var target_hp_after: int
var target_defeated: bool
var battle_result_before: int
var battle_result_after: int
var target_position := Vector3.ZERO
var objective_state_before: Dictionary = {}
var objective_state_after: Dictionary = {}
var presentation_completed := false
var presentation_suppressed := false
var presentation_error := ""

static func roll_hits(roll_value: float, chance: int) -> bool:
	return roll_value < float(clampi(chance, 0, 100))

func to_replay_record() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"kind": "attack",
		"actor": String(request.actor_id),
		"target": String(request.target_id),
		"transaction_id": transaction_id,
		"base_revision": base_revision,
		"committed_revision": committed_revision,
		"request": request.to_dictionary(),
		"resolved": resolved_dictionary(),
	}

func resolved_dictionary() -> Dictionary:
	return {
		"hit_chance": hit_chance,
		"roll_milli": roundi(roll * 1000.0),
		"did_hit": did_hit,
		"damage": damage,
		"actor_ap_before": actor_ap_before,
		"actor_ap_after": actor_ap_after,
		"target_hp_before": target_hp_before,
		"target_hp_after": target_hp_after,
		"target_defeated": target_defeated,
		"battle_result_before": battle_result_before,
		"battle_result_after": battle_result_after,
	}

func compare_resolved(expected: Dictionary) -> String:
	var actual := resolved_dictionary()
	for key in actual:
		if not expected.has(key):
			return "missing resolved field '%s'" % key
		if expected[key] != actual[key]:
			return "resolved field '%s' differs: expected %s, got %s" % [key, expected[key], actual[key]]
	return ""

