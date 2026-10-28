class_name EnvironmentModulePlacement
extends RefCounted

var component_id: StringName
var origin: Vector2i
var rotation: int
var variation: int
var elevation: int
## Document-local identity. Blank only until first document capture/import.
var placement_id: String

func _init(id: StringName, at: Vector2i, quarter_turns := 0, variation_index := 0, base_elevation := 0, instance_id := "") -> void:
	component_id = id
	origin = at
	rotation = posmod(quarter_turns, 4)
	variation = variation_index
	elevation = base_elevation
	placement_id = instance_id

func copy() -> EnvironmentModulePlacement:
	return EnvironmentModulePlacement.new(component_id, origin, rotation, variation, elevation, placement_id)

func signature() -> String:
	return "%s@%d,%d,%d:r%d:v%d" % [component_id, origin.x, elevation, origin.y, rotation, variation]

## Shared creation/capture allocator. Document callers supply their persistent
## next counter so deleting an object never makes its identity reusable.
static func ensure_identities(placements: Array, next_id := 1) -> int:
	var occupied := {}
	for placement: EnvironmentModulePlacement in placements:
		if placement.placement_id.is_empty(): continue
		occupied[placement.placement_id] = true
		if placement.placement_id.begins_with("placement_"):
			next_id = maxi(next_id, placement.placement_id.trim_prefix("placement_").to_int() + 1)
	for placement: EnvironmentModulePlacement in placements:
		if not placement.placement_id.is_empty(): continue
		while occupied.has("placement_%04d" % next_id): next_id += 1
		placement.placement_id = "placement_%04d" % next_id
		occupied[placement.placement_id] = true
		next_id += 1
	return next_id

## JSON-safe transform/identity shared by battlefield and chunk sources.
func to_record() -> Dictionary:
	return {"placement_id": placement_id, "component_id": str(component_id), "origin": [origin.x, origin.y], "rotation": rotation, "variation": variation, "elevation": elevation}

## Caller must validate source shape first; never use this to repair malformed data.
static func from_record(record: Dictionary) -> EnvironmentModulePlacement:
	return EnvironmentModulePlacement.new(StringName(record.component_id), Vector2i(int(record.origin[0]), int(record.origin[1])), int(record.rotation), int(record.variation), int(record.elevation), str(record.placement_id))
