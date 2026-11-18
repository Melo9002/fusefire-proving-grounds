class_name AIMovementProfiles
extends RefCounted
## The catalog of movement profiles and the rules that choose which of them apply to a unit right now.
## Selection is explicit and explained: every result carries the layers (applied in order, each one
## multiplying the position score terms) and a plain-language reason. It reads state and decides nothing
## about legality; the same candidate cells, safety checks and squad vetoes apply whichever profile is chosen.

const DEFAULT := preload("res://systems/ai/profiles/default.tres")
const OBJECTIVE_ROUTE := preload("res://systems/ai/profiles/objective_route.tres")
const CARRIER := preload("res://systems/ai/profiles/carrier.tres")

static func all() -> Array[AIMovementProfile]:
	return [DEFAULT, OBJECTIVE_ROUTE, CARRIER]

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
## Returns {"layers": Array[AIMovementProfile], "ids": Array[String], "reason": String}.
static func select(unit: TacticalUnit, objective_route: bool, intent_label: String) -> Dictionary:
	var layers: Array[AIMovementProfile] = []
	var reasons: Array[String] = []
	if objective_route:
		layers.append(OBJECTIVE_ROUTE)
		reasons.append("%s: the mission intent is %s" % [OBJECTIVE_ROUTE.display_name, intent_label])
	if is_instance_valid(unit) and unit.is_carrying_unit():
		layers.append(CARRIER)
		reasons.append("%s: carrying a casualty" % CARRIER.display_name)
	var ids: Array[String] = []
	for layer in layers:
		ids.append(String(layer.profile_id))
	if layers.is_empty():
		ids.append(String(DEFAULT.profile_id))
		reasons.append("%s: no situational change" % DEFAULT.display_name)
	return {"layers": layers, "ids": ids, "reason": "; ".join(reasons)}
