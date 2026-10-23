class_name EnvironmentParcelSpatialContract
extends RefCounted
## Small, serializable vocabulary for parcel ownership and functional access.
## Frontage spans use half-open grid-line endpoints in world X/Z coordinates.

const FRONTAGE_TO_STREET := "frontage_to_street"
const PEDESTRIAN_ACCESS := "pedestrian_access"
const LOADING_ACCESS := "loading_access"
const SERVICE_CLEARANCE := "service_clearance"
const REQUIRED_OCCUPANT := "required_occupant"

const FUNCTIONAL_RELATIONSHIPS := [
	FRONTAGE_TO_STREET,
	PEDESTRIAN_ACCESS,
	LOADING_ACCESS,
	SERVICE_CLEARANCE,
	REQUIRED_OCCUPANT,
]

static func frontage_spans(bounds: Rect2i, adjacent_road_cells: Dictionary, parcel_id := "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ordinal := 0
	for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var run_start := -1
		var run_end := -1
		var road_refs: Array[String] = []
		var length := bounds.size.x if direction.y != 0 else bounds.size.y
		for offset in length + 1:
			var adjacent := _adjacent_cell(bounds, direction, offset) if offset < length else Vector2i.ZERO
			var has_road := offset < length and adjacent_road_cells.has(adjacent)
			if has_road:
				if run_start < 0: run_start = offset
				run_end = offset + 1
				var road_ref := str(adjacent_road_cells[adjacent])
				if not road_ref.is_empty() and road_ref not in road_refs: road_refs.append(road_ref)
			elif run_start >= 0:
				road_refs.sort()
				var endpoints := _boundary_endpoints(bounds, direction, run_start, run_end)
				result.append({
					"frontage_id": "%s_frontage_%02d" % [parcel_id, ordinal] if not parcel_id.is_empty() else "frontage_%02d" % ordinal,
					"outward_direction": [direction.x, direction.y],
					"start": [endpoints[0].x, endpoints[0].y],
					"end": [endpoints[1].x, endpoints[1].y],
					"width_cells": run_end - run_start,
					"clearance_depth_cells": 1,
					"road_refs": road_refs.duplicate(),
				})
				ordinal += 1
				run_start = -1
				run_end = -1
				road_refs.clear()
	return result

static func directions_for_spans(spans: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for span in spans:
		if not span is Dictionary: continue
		var encoded = span.get("outward_direction", [])
		if not encoded is Array or encoded.size() != 2: continue
		var direction := Vector2i(int(encoded[0]), int(encoded[1]))
		if direction not in result: result.append(direction)
	return result

static func relationship_kind_for_template(template_id: String) -> String:
	if template_id.begins_with("building_frontage/") or template_id in ["public_forecourt", "service_alley"]:
		return PEDESTRIAN_ACCESS
	if template_id in ["loading_bay", "industrial_yard_block", "staging_pad"]:
		return LOADING_ACCESS
	if template_id == "equipment_compound":
		return SERVICE_CLEARANCE
	return ""

static func _adjacent_cell(bounds: Rect2i, direction: Vector2i, offset: int) -> Vector2i:
	match direction:
		Vector2i.UP: return Vector2i(bounds.position.x + offset, bounds.position.y - 1)
		Vector2i.RIGHT: return Vector2i(bounds.end.x, bounds.position.y + offset)
		Vector2i.DOWN: return Vector2i(bounds.position.x + offset, bounds.end.y)
		_: return Vector2i(bounds.position.x - 1, bounds.position.y + offset)

static func _boundary_endpoints(bounds: Rect2i, direction: Vector2i, first: int, last: int) -> Array[Vector2i]:
	match direction:
		Vector2i.UP: return [Vector2i(bounds.position.x + first, bounds.position.y), Vector2i(bounds.position.x + last, bounds.position.y)]
		Vector2i.RIGHT: return [Vector2i(bounds.end.x, bounds.position.y + first), Vector2i(bounds.end.x, bounds.position.y + last)]
		Vector2i.DOWN: return [Vector2i(bounds.position.x + first, bounds.end.y), Vector2i(bounds.position.x + last, bounds.end.y)]
		_: return [Vector2i(bounds.position.x, bounds.position.y + first), Vector2i(bounds.position.x, bounds.position.y + last)]
