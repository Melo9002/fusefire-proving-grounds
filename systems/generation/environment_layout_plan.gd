class_name EnvironmentLayoutPlan
extends RefCounted

var environment_id: StringName
var generation_seed: int
var topology: StringName
var macro_size := 10
var road_cells: Array[Vector2i] = []
var parcels: Array[Dictionary] = []
var rejected_candidates: Array[String] = []
var decisions: Array[String] = []
var fallback_used := false
var search_attempts := 0

func _init(id := &"industrial_district", map_seed := 0) -> void:
	environment_id = id
	generation_seed = map_seed

func signature() -> String:
	var roads: Array[String] = []
	for cell in road_cells:
		roads.append("%d,%d" % [cell.x, cell.y])
	roads.sort()
	var parcel_parts: Array[String] = []
	for parcel in parcels:
		var bounds: Rect2i = parcel.bounds
		parcel_parts.append("%s@%d,%d:%d,%d:%s:r%d" % [parcel.id, bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y, parcel.get("template", &"empty"), int(parcel.get("rotation", 0))])
	parcel_parts.sort()
	return "%s:%d:%s:%s:%s" % [environment_id, generation_seed, topology, "|".join(roads), "|".join(parcel_parts)]
