class_name AIDifficultyPolicy
extends RefCounted

enum Tier { EASY, NORMAL, HARD }

var tier: Tier = Tier.NORMAL
var expected_damage_weight := 1.0
var wounded_target_weight := 1.0
## How much the wound bonus depends on the chance that at least one affordable shot connects.
var wound_reliability_weight := 0.0
var finishing_bonus_weight := 1.0
var focus_penalty_weight := 1.0
var movement_progress_weight := 1.0
var crowding_penalty_weight := 1.0
var survival_cover_weight := 1.0
var survival_separation_weight := 1.0
var safe_advance_exposure_tolerance := 0.01
var position_cover_weight := 1.0
var position_exposure_weight := 1.0
var position_firing_weight := 1.0
var position_danger_weight := 1.0
var target_vip_weight := 1.0
var target_threat_weight := 1.0
var target_mission_weight := 1.0
var lapse_chance := 0.08
var lapse_score_margin := 12.0
## Whether a unit with a legal shot also weighs "move, then fire" against shooting from where it
## stands. Easy keeps the older shoot-if-you-can behavior; difficulty tuning is milestone 05 step 10.
var plans_repositioning := true

static func get_label(selected_tier: Tier) -> String:
	match selected_tier:
		Tier.EASY:
			return "Easy"
		Tier.HARD:
			return "Hard"
	return "Normal"

static func create(selected_tier: Tier) -> AIDifficultyPolicy:
	var policy := AIDifficultyPolicy.new()
	policy.tier = selected_tier
	match selected_tier:
		Tier.EASY:
			policy.lapse_chance = 0.22
			policy.lapse_score_margin = 15.0
			policy.plans_repositioning = false
			policy.wounded_target_weight = 0.35
			policy.finishing_bonus_weight = 0.25
			policy.focus_penalty_weight = 0.25
			policy.movement_progress_weight = 1.1
			policy.crowding_penalty_weight = 0.5
			policy.survival_cover_weight = 0.6
			policy.survival_separation_weight = 0.6
			policy.safe_advance_exposure_tolerance = 0.4
			policy.position_cover_weight = 0.6
			policy.position_exposure_weight = 0.55
			policy.position_firing_weight = 0.7
			policy.position_danger_weight = 0.6
			policy.target_vip_weight = 0.6
			policy.target_threat_weight = 0.55
			policy.target_mission_weight = 0.6
		Tier.HARD:
			policy.lapse_chance = 0.0
			policy.wounded_target_weight = 1.3
			policy.wound_reliability_weight = 1.0
			policy.finishing_bonus_weight = 1.5
			policy.focus_penalty_weight = 0.7
			policy.crowding_penalty_weight = 1.2
			policy.survival_cover_weight = 1.35
			policy.survival_separation_weight = 1.2
			policy.position_cover_weight = 1.3
			policy.position_exposure_weight = 1.35
			policy.position_firing_weight = 1.25
			policy.position_danger_weight = 1.4
			policy.target_vip_weight = 1.2
			policy.target_threat_weight = 1.35
			policy.target_mission_weight = 1.4
	return policy

func choose_near_best_index(scores: Array[float], rng: RandomNumberGenerator) -> int:
	if tier == Tier.HARD or scores.size() < 2:
		return 0
	var eligible: Array[int] = []
	for index in range(1, scores.size()):
		if scores[0] - scores[index] <= lapse_score_margin:
			eligible.append(index)
	if eligible.is_empty() or rng.randf() >= lapse_chance:
		return 0
	return eligible[rng.randi_range(0, eligible.size() - 1)]

func score_target(missing_hp: int, current_hp: int, focus_adjustment: float, predicted_damage := -1) -> float:
	var damage: int = CombatRules.cover_tuning.damage_for_hit(1.0) if predicted_damage < 0 else predicted_damage
	var finisher := 20.0 if damage > 0 and current_hp <= damage else 0.0
	return missing_hp * wounded_target_weight + finisher * finishing_bonus_weight + focus_adjustment * focus_penalty_weight

func score_path_progress(step_index: int, squad_adjustment: float) -> float:
	return step_index * movement_progress_weight + squad_adjustment * crowding_penalty_weight

func permits_advance(current_exposure: float, candidate_exposure: float) -> bool:
	return candidate_exposure <= current_exposure + safe_advance_exposure_tolerance
