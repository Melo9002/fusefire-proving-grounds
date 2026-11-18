class_name TacticalArchetypeCatalog
extends RefCounted

const GENERIC_ID := &"generic"
const DEFINITIONS: Array[TacticalArchetype] = [
	preload("res://units/archetypes/generic.tres"),
	preload("res://units/archetypes/shieldbearer.tres"),
	preload("res://units/archetypes/marksman.tres"),
	preload("res://units/archetypes/sentinel.tres"),
	preload("res://units/archetypes/support.tres"),
	preload("res://units/archetypes/bulwark.tres"),
]

static func all() -> Array[TacticalArchetype]:
	return DEFINITIONS.duplicate()

static func get_definition(archetype_id: StringName) -> TacticalArchetype:
	for definition in DEFINITIONS:
		if definition.archetype_id == archetype_id:
			return definition
	return null

static func resolve_or_generic(archetype_id: StringName, report_invalid := true) -> TacticalArchetype:
	var definition := get_definition(archetype_id)
	if definition:
		return definition
	if report_invalid:
		push_warning("[TacticalArchetypeCatalog] Unknown archetype '%s'; using Generic." % archetype_id)
	return get_definition(GENERIC_ID)

## Identity of the Shield settings of the given archetypes (the distinct ones, in a fixed order). An
## archetype that no longer exists, or lost its Shield, changes the identity instead of being ignored.
static func shield_signature(archetype_ids: Array) -> String:
	var distinct: Array[String] = []
	for id in archetype_ids:
		var text := String(id)
		if not distinct.has(text): distinct.append(text)
	distinct.sort()
	var parts: Array[String] = []
	for text in distinct:
		var definition := get_definition(StringName(text))
		var capability: ShieldCapability = definition.shield_capability if definition else null
		parts.append("%s=%s" % [text, "missing" if definition == null else (capability.signature() if capability else "none")])
	return "shield-set-1:" + "|".join(parts).sha256_text()

static func normalize_ids(values: Array[StringName], count: int) -> Array[StringName]:
	var normalized: Array[StringName] = []
	for index in maxi(0, count):
		var requested := values[index] if index < values.size() else GENERIC_ID
		normalized.append(requested if get_definition(requested) else GENERIC_ID)
	return normalized

static func validate_catalog() -> Array[String]:
	var issues: Array[String] = []
	var seen: Dictionary = {}
	for definition in DEFINITIONS:
		var issue := definition.validation_message()
		if not issue.is_empty(): issues.append(issue)
		if seen.has(definition.archetype_id): issues.append("Duplicate archetype ID: %s" % definition.archetype_id)
		seen[definition.archetype_id] = true
	if not seen.has(GENERIC_ID): issues.append("Generic archetype is missing")
	return issues
