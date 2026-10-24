class_name EnvironmentLayoutPlan
extends RefCounted

var environment_id: StringName
var generation_seed: int
var topology: StringName
var macro_size := 10
var road_cells: Array[Vector2i] = []
var parcels: Array[Dictionary] = []
var reservations: Array[Dictionary] = []
var relationship_failures: Array[Dictionary] = []
var rejected_candidates: Array[String] = []
var candidate_rejections: Array[Dictionary] = []
var parcel_search_reports: Array[Dictionary] = []
var search_budget: Dictionary = {}
var decisions: Array[String] = []
var fallback_used := false
var search_attempts := 0
var optional_dressing_failures := 0
var search_budget_exhaustions := 0

func _init(id := &"industrial_district", map_seed := 0) -> void:
	environment_id = id
	generation_seed = map_seed

func generation_summary() -> Dictionary:
	var rejection_causes: Dictionary = {}
	for rejection in candidate_rejections:
		var code := str(rejection.get("code", "UNKNOWN_REJECTION"))
		rejection_causes[code] = int(rejection_causes.get(code, 0)) + 1
	var functional := 0
	var buffers := 0
	var fallbacks := 0
	for parcel in parcels:
		if parcel.get("template", &"") == &"district_buffer": buffers += 1
		else: functional += 1
		if not str(parcel.get("fallback_reason", "")).is_empty(): fallbacks += 1
	return {
		"attempted_parcels": parcel_search_reports.size(),
		"functional_parcels": functional,
		"buffer_parcels": buffers,
		"fallback_outcomes": fallbacks,
		"candidate_attempts": search_attempts,
		"candidate_rejections": candidate_rejections.size(),
		"rejection_causes": rejection_causes,
		"optional_dressing_failures": optional_dressing_failures,
		"search_budget_exhaustions": search_budget_exhaustions,
		"relationship_failures": relationship_failures.size(),
	}

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
		parcel_parts.append("%s@%d,%d:%d,%d:%s:r%d:f%s:o%d:s%s" % [parcel.id, bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y, parcel.get("template", &"empty"), int(parcel.get("rotation", 0)), parcel.get("selected_frontage_id", ""), int(parcel.get("placement_offset", 0)), spatial_signature])
	parcel_parts.sort()
	var reservation_parts: Array[String] = []
	for reservation in reservations:
		var cells: Array[String] = []
		for cell: Vector2i in reservation.get("cells", []): cells.append("%d,%d" % [cell.x, cell.y])
		cells.sort()
		reservation_parts.append("%s:%s:%s:%s" % [reservation.get("reservation_id", ""), reservation.get("role", ""), reservation.get("owner_ref", ""), ";".join(cells)])
	reservation_parts.sort()
	var relationship_parts: Array[String] = []
	for failure in relationship_failures:
		relationship_parts.append("%s:%s:%s" % [failure.get("code", ""), failure.get("parcel_id", ""), failure.get("reference", "")])
	relationship_parts.sort()
	var search_parts: Array[String] = []
	for report in parcel_search_reports:
		search_parts.append("%s:%s:%s:%s" % [report.get("parcel_id", ""), report.get("attempts", 0), report.get("accepted_candidate", ""), report.get("outcome", "")])
	search_parts.sort()
	return "%s:%d:%s:%s:%s:%s:%s:%s" % [environment_id, generation_seed, topology, "|".join(roads), "|".join(parcel_parts), "|".join(reservation_parts), "|".join(relationship_parts), "|".join(search_parts)]
