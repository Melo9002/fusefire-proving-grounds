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
		var frontages: Array[String] = []
		for span in parcel.get("frontage_spans", []):
			frontages.append("%s:%s>%s:%s" % [span.get("outward_direction", []), span.get("start", []), span.get("end", []), span.get("road_refs", [])])
		frontages.sort()
		var occupants: Array[String] = []
		for occupant in parcel.get("occupants", []):
			occupants.append("%s:%s" % [occupant.get("placement_signature", occupant.get("placement_ref", "")), occupant.get("required", true)])
		occupants.sort()
		var spatial_signature := ("f[%s]:o[%s]" % [";".join(frontages), ";".join(occupants)]).sha256_text()
		parcel_parts.append("%s@%d,%d:%d,%d:%s:r%d:s%s" % [parcel.id, bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y, parcel.get("template", &"empty"), int(parcel.get("rotation", 0)), spatial_signature])
	parcel_parts.sort()
	return "%s:%d:%s:%s:%s" % [environment_id, generation_seed, topology, "|".join(roads), "|".join(parcel_parts)]
