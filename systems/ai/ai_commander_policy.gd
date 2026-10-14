class_name AICommanderPolicy
extends RefCounted

## Immutable squad doctrine. Difficulty owns decision quality and bounded lapses;
## this policy owns preferences. Default is the compatibility baseline.
enum Profile { DEFAULT, CAUTIOUS, AGGRESSIVE }
enum StrategicIntent { BALANCED_ENGAGEMENT }

const CAUTIOUS_MULTIPLIERS := {
	&"movement_progress_weight": 0.95,
	&"crowding_penalty_weight": 1.15,
	&"survival_separation_weight": 1.10,
	&"position_cover_weight": 1.30,
	&"position_exposure_weight": 1.30,
	&"position_firing_weight": 0.90,
	&"position_danger_weight": 1.35,
}
const CAUTIOUS_SAFE_ADVANCE_DELTA := -0.10
const AGGRESSIVE_MULTIPLIERS := {
	&"wounded_target_weight": 1.15,
	&"finishing_bonus_weight": 1.25,
	&"movement_progress_weight": 1.20,
	&"position_cover_weight": 0.90,
	&"position_exposure_weight": 0.85,
	&"position_firing_weight": 1.20,
	&"position_danger_weight": 0.90,
	&"target_threat_weight": 1.10,
}
const AGGRESSIVE_SAFE_ADVANCE_DELTA := 0.15
const COMPOSED_FIELDS: Array[StringName] = [
	&"wounded_target_weight", &"finishing_bonus_weight", &"movement_progress_weight",
	&"crowding_penalty_weight", &"survival_separation_weight", &"position_cover_weight",
	&"position_exposure_weight", &"position_firing_weight", &"position_danger_weight",
	&"target_threat_weight",
]

var _profile: Profile = Profile.DEFAULT
var profile: Profile:
	get: return _profile

static func create(selected_profile: Profile = Profile.DEFAULT) -> AICommanderPolicy:
	var policy := AICommanderPolicy.new()
	policy._profile = selected_profile
	return policy

static func get_label(selected_profile: Profile) -> String:
	match selected_profile:
		Profile.AGGRESSIVE:
			return "Aggressive"
		Profile.CAUTIOUS:
			return "Cautious"
		Profile.DEFAULT:
			return "Default"
	return "Default"

func get_policy_id() -> StringName:
	match _profile:
		Profile.CAUTIOUS:
			return &"cautious"
		Profile.AGGRESSIVE:
			return &"aggressive"
	return &"default"

func get_strategic_intent() -> StrategicIntent:
	return StrategicIntent.BALANCED_ENGAGEMENT

func get_strategic_intent_label() -> String:
	return "Balanced engagement"

## Build the unit-level policy consumed by the existing scorers. Commander
## Difficulty lapse chance and margin pass through unchanged.
func compose(difficulty: AIDifficultyPolicy) -> AIDifficultyPolicy:
	var composed := AIDifficultyPolicy.new()
	composed.tier = difficulty.tier
	composed.wounded_target_weight = _multiply(&"wounded_target_weight", difficulty.wounded_target_weight)
	composed.finishing_bonus_weight = _multiply(&"finishing_bonus_weight", difficulty.finishing_bonus_weight)
	composed.focus_penalty_weight = difficulty.focus_penalty_weight
	composed.movement_progress_weight = _multiply(&"movement_progress_weight", difficulty.movement_progress_weight)
	composed.crowding_penalty_weight = _multiply(&"crowding_penalty_weight", difficulty.crowding_penalty_weight)
	# Preserved for compatibility; this existing parameter remains inactive.
	composed.survival_cover_weight = difficulty.survival_cover_weight
	composed.survival_separation_weight = _multiply(&"survival_separation_weight", difficulty.survival_separation_weight)
	composed.safe_advance_exposure_tolerance = maxf(0.0, difficulty.safe_advance_exposure_tolerance + _safe_advance_delta())
	composed.position_cover_weight = _multiply(&"position_cover_weight", difficulty.position_cover_weight)
	composed.position_exposure_weight = _multiply(&"position_exposure_weight", difficulty.position_exposure_weight)
	composed.position_firing_weight = _multiply(&"position_firing_weight", difficulty.position_firing_weight)
	composed.position_danger_weight = _multiply(&"position_danger_weight", difficulty.position_danger_weight)
	composed.target_vip_weight = difficulty.target_vip_weight
	composed.target_threat_weight = _multiply(&"target_threat_weight", difficulty.target_threat_weight)
	composed.target_mission_weight = difficulty.target_mission_weight
	composed.lapse_chance = difficulty.lapse_chance
	composed.lapse_score_margin = difficulty.lapse_score_margin
	return composed

func composition_snapshot(difficulty: AIDifficultyPolicy, composed: AIDifficultyPolicy) -> Dictionary:
	var result := {}
	for field: StringName in COMPOSED_FIELDS:
		result[String(field)] = {
			"base": difficulty.get(field),
			"multiplier": _multiplier(field),
			"final": composed.get(field),
		}
	result["safe_advance_exposure_tolerance"] = {
		"base": difficulty.safe_advance_exposure_tolerance,
		"delta": _safe_advance_delta(),
		"final": composed.safe_advance_exposure_tolerance,
	}
	return result

func _multiply(field: StringName, value: float) -> float:
	return value * _multiplier(field)

func _multiplier(field: StringName) -> float:
	if _profile == Profile.CAUTIOUS:
		return float(CAUTIOUS_MULTIPLIERS.get(field, 1.0))
	if _profile == Profile.AGGRESSIVE:
		return float(AGGRESSIVE_MULTIPLIERS.get(field, 1.0))
	return 1.0

func _safe_advance_delta() -> float:
	match _profile:
		Profile.CAUTIOUS:
			return CAUTIOUS_SAFE_ADVANCE_DELTA
		Profile.AGGRESSIVE:
			return AGGRESSIVE_SAFE_ADVANCE_DELTA
	return 0.0
