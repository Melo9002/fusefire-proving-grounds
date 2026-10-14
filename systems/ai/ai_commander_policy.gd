class_name AICommanderPolicy
extends RefCounted

## Immutable squad doctrine. Difficulty owns decision quality and bounded lapses;
## this policy owns future preferences. Only the identity Default doctrine exists.
enum Profile { DEFAULT }
enum StrategicIntent { BALANCED_ENGAGEMENT }

var profile: Profile = Profile.DEFAULT

static func create(selected_profile: Profile = Profile.DEFAULT) -> AICommanderPolicy:
	var policy := AICommanderPolicy.new()
	policy.profile = selected_profile
	return policy

static func get_label(selected_profile: Profile) -> String:
	match selected_profile:
		Profile.DEFAULT:
			return "Default"
	return "Default"

func get_policy_id() -> StringName:
	return &"default"

func get_strategic_intent() -> StrategicIntent:
	return StrategicIntent.BALANCED_ENGAGEMENT

func get_strategic_intent_label() -> String:
	return "Balanced engagement"

## Build the unit-level policy consumed by the existing scorers. Commander
## multipliers are deliberately identity values until a profile is authorized.
## Difficulty lapse chance and margin pass through unchanged.
func compose(difficulty: AIDifficultyPolicy) -> AIDifficultyPolicy:
	var composed := AIDifficultyPolicy.new()
	composed.tier = difficulty.tier
	composed.wounded_target_weight = difficulty.wounded_target_weight
	composed.finishing_bonus_weight = difficulty.finishing_bonus_weight
	composed.focus_penalty_weight = difficulty.focus_penalty_weight
	composed.movement_progress_weight = difficulty.movement_progress_weight
	composed.crowding_penalty_weight = difficulty.crowding_penalty_weight
	# Preserved for compatibility; this existing parameter remains inactive.
	composed.survival_cover_weight = difficulty.survival_cover_weight
	composed.survival_separation_weight = difficulty.survival_separation_weight
	composed.safe_advance_exposure_tolerance = difficulty.safe_advance_exposure_tolerance
	composed.position_cover_weight = difficulty.position_cover_weight
	composed.position_exposure_weight = difficulty.position_exposure_weight
	composed.position_firing_weight = difficulty.position_firing_weight
	composed.position_danger_weight = difficulty.position_danger_weight
	composed.target_vip_weight = difficulty.target_vip_weight
	composed.target_threat_weight = difficulty.target_threat_weight
	composed.target_mission_weight = difficulty.target_mission_weight
	composed.lapse_chance = difficulty.lapse_chance
	composed.lapse_score_margin = difficulty.lapse_score_margin
	return composed
