class_name EnvironmentParcelCandidateSearch
extends RefCounted
## Fixed-budget, deterministic local choices for existing parcel recipes.
## This enumerates authored alternatives; it does not invent transforms or
## perform recursive/global backtracking.

const RelationshipValidator = preload("res://systems/generation/environment_parcel_relationship_validator.gd")

const MAX_TEMPLATE_CHOICES := 6
const MAX_FRONTAGES_PER_TEMPLATE := 4
const MAX_TANGENT_OFFSETS_PER_FRONTAGE := 3
const MAX_CANDIDATE_ATTEMPTS_PER_PARCEL := 12
const MAX_OPTIONAL_REMOVALS_PER_CANDIDATE := 2

static func specifications(parcel: Dictionary, templates: Array[StringName], catalog: Dictionary) -> Array[Dictionary]:
	var primary: Array[Dictionary] = []
	var alternate_frontages: Array[Dictionary] = []
	var alternate_offsets: Array[Dictionary] = []
	for template_id in templates.slice(0, mini(MAX_TEMPLATE_CHOICES, templates.size())):
		var template_name := String(template_id)
		var contract := RelationshipValidator.contract_for(template_name)
		if contract.is_empty():
			primary.append(_spec(template_id, {}, 0))
			continue
		var frontages := RelationshipValidator.frontage_candidates(parcel, template_name)
		if frontages.is_empty():
			primary.append(_spec(template_id, {}, 0))
			continue
		frontages = frontages.slice(0, mini(MAX_FRONTAGES_PER_TEMPLATE, frontages.size()))
		primary.append(_spec(template_id, frontages[0], 0))
		for index in range(1, frontages.size()):
			alternate_frontages.append(_spec(template_id, frontages[index], 0))
		var offsets := supported_tangent_offsets(template_id, parcel, catalog)
		for frontage in frontages:
			for offset in offsets.slice(1, mini(MAX_TANGENT_OFFSETS_PER_FRONTAGE, offsets.size())):
				alternate_offsets.append(_spec(template_id, frontage, offset))
	return primary + alternate_frontages + alternate_offsets

static func supported_tangent_offsets(template_id: StringName, parcel: Dictionary, catalog: Dictionary) -> Array[int]:
	var result: Array[int] = [0]
	var template_name := String(template_id)
	if not template_name.begins_with("building_frontage/"): return result
	var shell_id := StringName(template_name.trim_prefix("building_frontage/"))
	var shell: EnvironmentModuleDefinition = catalog.get(shell_id)
	var bounds: Rect2i = parcel.get("bounds", Rect2i())
	if shell == null or bounds.size.x <= shell.size.x: return result
	var margin := bounds.size.x - shell.size.x
	var centered := floori(float(margin) * 0.5)
	if centered >= 1: result.append(-1)
	if margin - centered >= 1: result.append(1)
	return result

static func candidate_seed(map_seed: int, parcel_id: String, specification: Dictionary) -> int:
	var key := "%d|%s|%s|%s|%d" % [map_seed, parcel_id, specification.get("template_id", ""), specification.get("frontage_id", ""), specification.get("tangent_offset", 0)]
	return map_seed ^ key.hash()

static func budget_exhausted(candidate_count: int, attempted: int, accepted: bool) -> bool:
	return not accepted and attempted >= MAX_CANDIDATE_ATTEMPTS_PER_PARCEL and candidate_count > attempted

static func configuration() -> Dictionary:
	return {
		"max_template_choices": MAX_TEMPLATE_CHOICES,
		"max_frontages_per_template": MAX_FRONTAGES_PER_TEMPLATE,
		"max_tangent_offsets_per_frontage": MAX_TANGENT_OFFSETS_PER_FRONTAGE,
		"max_candidate_attempts_per_parcel": MAX_CANDIDATE_ATTEMPTS_PER_PARCEL,
		"max_optional_removals_per_candidate": MAX_OPTIONAL_REMOVALS_PER_CANDIDATE,
	}

static func _spec(template_id: StringName, frontage: Dictionary, offset: int) -> Dictionary:
	return {
		"template_id": template_id,
		"frontage": frontage.duplicate(true),
		"frontage_id": str(frontage.get("frontage_id", "")),
		"rotation": RelationshipValidator.rotation_for_frontage(String(template_id), frontage) if not frontage.is_empty() else 0,
		"tangent_offset": offset,
	}
