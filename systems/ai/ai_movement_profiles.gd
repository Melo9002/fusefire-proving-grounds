class_name AIMovementProfiles
extends RefCounted
## The catalog of movement profiles and the rules that choose which of them apply to a unit right now.
## Selection is explicit and explained: every result carries the layers (applied in order, each one
## multiplying the position score terms) and a plain-language reason. It reads state and decides nothing
## about legality; the same candidate cells, safety checks and squad vetoes apply whichever profile is chosen.

const DEFAULT := preload("res://systems/ai/profiles/default.tres")
const OBJECTIVE_ROUTE := preload("res://systems/ai/profiles/objective_route.tres")
const CARRIER := preload("res://systems/ai/profiles/carrier.tres")
const ESCORT := preload("res://systems/ai/profiles/escort.tres")
const DEFENSIVE := preload("res://systems/ai/profiles/defensive.tres")
const AGGRESSIVE := preload("res://systems/ai/profiles/aggressive.tres")
const FLANKING := preload("res://systems/ai/profiles/flanking.tres")
const SUPPORT := preload("res://systems/ai/profiles/support.tres")

## Thresholds of the stance rules; kept here so they are easy to find and adjust.
const WOUNDED_FRACTION := 0.4
const HEALTHY_FRACTION := 0.7
const OUTMATCHED_BY := 2
const WOUNDED_ALLY_FRACTION := 0.5

static func all() -> Array[AIMovementProfile]:
	return [DEFAULT, OBJECTIVE_ROUTE, CARRIER, ESCORT, DEFENSIVE, AGGRESSIVE, FLANKING, SUPPORT]

static func get_profile(profile_id: StringName) -> AIMovementProfile:
	for profile in all():
		if profile.profile_id == profile_id:
			return profile
	return null

static func validate_catalog() -> Array[String]:
	var issues: Array[String] = []
	var seen := {}
	for profile in all():
		if profile.profile_id.is_empty(): issues.append("A movement profile has no ID")
		if seen.has(profile.profile_id): issues.append("Duplicate movement profile ID: %s" % profile.profile_id)
		seen[profile.profile_id] = true
	if not seen.has(DEFAULT.profile_id): issues.append("The default movement profile is missing")
	return issues

## The layers that apply to `unit` for one movement decision, in the order they multiply the score, and why.
## `objective_route` is true when the mission intent is a route (reach, extract, rescue, terminal);
## `intent_label` names that intent for the explanation.
## `situation` holds the facts the stance rules read (all optional, so an empty dictionary means none apply):
##   hp_fraction, out_of_ammo, threats (hostiles that can shoot the unit now), nearby_allies, wounded_target,
##   escorting, flank_possible, wounded_ally, support_unit.
## Context layers (objective route, carrier) come first; then at most ONE stance, chosen in this order:
## escort, defensive, support, flanking, aggressive. A carrier takes no stance, and a unit on an objective
## route takes only the escort stance, so tactical stances never pull a mission unit off its goal.
## Returns {"layers": Array[AIMovementProfile], "ids": Array[String], "reason": String}.
static func select(unit: TacticalUnit, objective_route: bool, intent_label: String, situation: Dictionary = {}) -> Dictionary:
	var layers: Array[AIMovementProfile] = []
	var reasons: Array[String] = []
	if objective_route:
		layers.append(OBJECTIVE_ROUTE)
		reasons.append("%s: the mission intent is %s" % [OBJECTIVE_ROUTE.display_name, intent_label])
	if is_instance_valid(unit) and unit.is_carrying_unit():
		layers.append(CARRIER)
		reasons.append("%s: carrying a casualty" % CARRIER.display_name)
	var carrying := is_instance_valid(unit) and unit.is_carrying_unit()
	var stance := _stance(situation, objective_route) if not carrying else {}
	if not stance.is_empty():
		layers.append(stance.profile)
		reasons.append("%s: %s" % [stance.profile.display_name, stance.reason])
	var ids: Array[String] = []
	for layer in layers:
		ids.append(String(layer.profile_id))
	if layers.is_empty():
		ids.append(String(DEFAULT.profile_id))
		reasons.append("%s: no situational change" % DEFAULT.display_name)
	return {"layers": layers, "ids": ids, "reason": "; ".join(reasons)}

## The stance for a free unit, or {} for none. {profile, reason}.
static func _stance(situation: Dictionary, objective_route: bool) -> Dictionary:
	if situation.is_empty():
		return {}
	if bool(situation.get("escorting", false)):
		return {"profile": ESCORT, "reason": "guarding the carrier"}
	if objective_route:
		return {}
	var hp := float(situation.get("hp_fraction", 1.0))
	var threats := int(situation.get("threats", 0))
	var allies := int(situation.get("nearby_allies", 0))
	if hp <= WOUNDED_FRACTION:
		return {"profile": DEFENSIVE, "reason": "badly hurt (%d%% HP)" % roundi(hp * 100.0)}
	if bool(situation.get("out_of_ammo", false)):
		return {"profile": DEFENSIVE, "reason": "out of ammunition"}
	if threats - allies >= OUTMATCHED_BY:
		return {"profile": DEFENSIVE, "reason": "outmatched (%d hostile(s) can shoot it, %d ally nearby)" % [threats, allies]}
	if bool(situation.get("support_unit", false)):
		return {"profile": SUPPORT, "reason": "a support unit"}
	if bool(situation.get("wounded_ally", false)):
		return {"profile": SUPPORT, "reason": "a nearby ally is hurt"}
	if bool(situation.get("flank_possible", false)):
		return {"profile": FLANKING, "reason": "an ally already has a shot at the target"}
	if hp >= HEALTHY_FRACTION and (bool(situation.get("wounded_target", false)) or (threats > 0 and allies + 1 - threats >= 1)):
		return {"profile": AGGRESSIVE, "reason": "healthy with %s" % ("a wounded target in reach" if bool(situation.get("wounded_target", false)) else "the local advantage")}
	return {}
