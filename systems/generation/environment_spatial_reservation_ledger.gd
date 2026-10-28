class_name EnvironmentSpatialReservationLedger
extends RefCounted
## Deterministic construction-time reservations. These records protect mission
## and functional access space; they never author MapData occupancy themselves.

const Spatial = preload("res://systems/generation/environment_spatial_queries.gd")
const WHOLE_COLUMN := "whole_column"
const FLOOR := "floor"

const DEPLOYMENT_REGION := "deployment_region"
const OBJECTIVE_REGION := "objective_region"
const PEDESTRIAN_ACCESS := "pedestrian_access"
const LOADING_SERVICE_APPROACH := "loading_service_approach"
const CIRCULATION_CLEARANCE := "circulation_clearance"

const ROLES := [
	DEPLOYMENT_REGION,
	OBJECTIVE_REGION,
	PEDESTRIAN_ACCESS,
	LOADING_SERVICE_APPROACH,
	CIRCULATION_CLEARANCE,
]

var reservations: Array[Dictionary] = []
var failures: Array[Dictionary] = []

static func from_map(data: MapData) -> EnvironmentSpatialReservationLedger:
	var result := EnvironmentSpatialReservationLedger.new()
	var zones: Array[MapZoneData] = []
	zones.append_array(data.get_zones_by_kind(MapZoneData.Kind.DEPLOYMENT))
	zones.append_array(data.get_zones_by_kind(MapZoneData.Kind.OBJECTIVE))
	zones.append_array(data.get_zones_by_kind(MapZoneData.Kind.EXTRACTION))
	zones.sort_custom(func(a, b): return String(a.zone_id) < String(b.zone_id))
	for zone in zones:
		var cells: Array[Vector2i] = []
		for cell in zone.cells:
			var horizontal := Vector2i(cell.x, cell.z)
			if horizontal not in cells: cells.append(horizontal)
		var role := DEPLOYMENT_REGION if zone.kind == MapZoneData.Kind.DEPLOYMENT else OBJECTIVE_REGION
		result.try_reserve({
			"reservation_id": "mission_%s" % zone.zone_id,
			"scope": WHOLE_COLUMN,
			"owner_ref": "zone:%s" % zone.zone_id,
			"role": role,
			"purpose": "deployment" if zone.kind == MapZoneData.Kind.DEPLOYMENT else ("extraction" if zone.kind == MapZoneData.Kind.EXTRACTION else "objective"),
			"cells": cells,
			"required": true,
			"source_ref": "zone:%s" % zone.zone_id,
		})
	return result

func duplicate_ledger() -> EnvironmentSpatialReservationLedger:
	var result := EnvironmentSpatialReservationLedger.new()
	result.reservations.assign(reservations.duplicate(true))
	result.failures.assign(failures.duplicate(true))
	return result

func validate_map_bounds(map_size: Vector2i) -> bool:
	var valid := true
	for reservation in reservations:
		for cell: Vector2i in reservation.cells:
			if cell.x < 0 or cell.y < 0 or cell.x >= map_size.x or cell.y >= map_size.y:
				_fail("RESERVATION_OUT_OF_BOUNDS", reservation.reservation_id, "%s contains out-of-bounds cell %s" % [reservation.reservation_id, cell])
				valid = false
	return valid

func try_reserve(value: Dictionary) -> bool:
	var record := value.duplicate(true)
	var reservation_id := str(record.get("reservation_id", ""))
	var owner_ref := str(record.get("owner_ref", ""))
	var role := str(record.get("role", ""))
	var cells := _normalized_cells(record.get("cells", []))
	if reservation_id.is_empty() or owner_ref.is_empty() or role not in ROLES or cells.is_empty():
		_fail("INVALID_RESERVATION", reservation_id, "reservation requires an identity, owner, supported role, and at least one cell")
		return false
	# Old two-dimensional records explicitly retain whole-column behavior.
	record["scope"] = str(record.get("scope", WHOLE_COLUMN))
	if record.scope not in [WHOLE_COLUMN, FLOOR]:
		_fail("INVALID_RESERVATION_SCOPE", reservation_id, "scope must be floor or whole_column")
		return false
	if record.scope == FLOOR:
		if not (record.get("elevation") is int or record.get("elevation") is float) or not is_finite(float(record.elevation)) or float(record.elevation) != floorf(float(record.elevation)) or float(record.elevation) < 0 or not (record.get("height") is int or record.get("height") is float) or not is_finite(float(record.height)) or float(record.height) <= 0:
			_fail("INVALID_RESERVATION_SPAN", reservation_id, "floor reservations require nonnegative integer elevation and positive finite height")
			return false
		record["elevation"] = int(record.elevation)
		record["height"] = float(record.height)
	if reservations.any(func(existing): return existing.reservation_id == reservation_id):
		_fail("DUPLICATE_RESERVATION", reservation_id, "reservation identity is already present")
		return false
	for existing in reservations:
		if Spatial.interval_intersects(reservation_span(record), reservation_span(existing)) and Spatial.cells_intersect(cells, existing.cells) and not roles_are_compatible(role, str(existing.role), owner_ref, str(existing.owner_ref)):
			_fail("INCOMPATIBLE_RESERVATION", reservation_id, "%s conflicts with %s" % [reservation_id, existing.reservation_id])
			return false
	record["cells"] = cells
	record["required"] = bool(record.get("required", true))
	record["validation_state"] = str(record.get("validation_state", "validated"))
	reservations.append(record)
	reservations.sort_custom(func(a, b): return str(a.reservation_id) < str(b.reservation_id))
	return true

func placement_allowed(definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement, _layout: EnvironmentModuleLayout, owner_ref := "") -> Dictionary:
	if definition.placement_layer == EnvironmentModuleDefinition.PlacementLayer.GROUND:
		return {"ok": true}
	var geometry := Spatial.record(definition, placement)
	for reservation in reservations:
		# A parcel validates its own occupants against the more precise functional
		# relationship contract after the batch is assembled. Allowing its owner
		# through here avoids treating a shell's authored frontage clearance as an
		# obstruction to its own access reservation. Other parcels and optional
		# road furniture remain blocked by the reservation.
		if not owner_ref.is_empty() and owner_ref == str(reservation.get("owner_ref", "")): continue
		var span := reservation_span(reservation)
		var footprint_hit := Spatial.interval_intersects(geometry.occupied_span, span) and Spatial.cells_intersect(geometry.cells, reservation.cells)
		var clearance_hit := Spatial.interval_intersects(geometry.clearance_span, span) and Spatial.cells_intersect(geometry.clearance, reservation.cells)
		var surface_hit := false
		for at: Vector3i in geometry.surfaces:
			if Vector2i(at.x, at.z) in reservation.cells and span.x <= at.y and at.y < span.y: surface_hit = true
		var visual_hit := definition.tactical_role == EnvironmentModuleDefinition.TacticalRole.VISUAL_ONLY and Spatial.visual_intersects_cells(geometry.visual, reservation.cells, span)
		if footprint_hit or clearance_hit or surface_hit or visual_hit:
			return {
				"ok": false,
				"code": "RESERVED_REGION_BLOCKED",
				"reservation_id": reservation.reservation_id,
				"owner_ref": owner_ref,
				"message": "%s intrudes into required %s '%s'" % [placement.component_id, reservation.role, reservation.reservation_id],
			}
	return {"ok": true}

func contains(role: String, cell: Vector2i) -> bool:
	# Deliberately projected query for existing two-dimensional parcel planning.
	return reservations.any(func(record): return record.role == role and record.cells.has(cell))

func contains_at(role: String, cell: Vector3i) -> bool:
	for record in reservations:
		var span := reservation_span(record)
		if record.role == role and Vector2i(cell.x, cell.z) in record.cells and span.x <= cell.y and cell.y < span.y: return true
	return false

static func roles_are_compatible(first: String, second: String, first_owner := "", second_owner := "") -> bool:
	if first_owner == second_owner and not first_owner.is_empty(): return true
	var access_roles := [PEDESTRIAN_ACCESS, LOADING_SERVICE_APPROACH, CIRCULATION_CLEARANCE]
	if first in access_roles and second in access_roles: return true
	if OBJECTIVE_REGION in [first, second] and (first in access_roles or second in access_roles): return true
	if DEPLOYMENT_REGION in [first, second] and CIRCULATION_CLEARANCE in [first, second]: return true
	if DEPLOYMENT_REGION in [first, second] and PEDESTRIAN_ACCESS in [first, second]: return true
	return false

static func frontage_access_cells(span: Dictionary, bounds: Rect2i, role: String) -> Array[Vector2i]:
	var start_data = span.get("start", [])
	var end_data = span.get("end", [])
	var direction_data = span.get("outward_direction", [])
	if not start_data is Array or not end_data is Array or not direction_data is Array or start_data.size() != 2 or end_data.size() != 2 or direction_data.size() != 2:
		return []
	var start := Vector2i(int(start_data[0]), int(start_data[1]))
	var end := Vector2i(int(end_data[0]), int(end_data[1]))
	var outward := Vector2i(int(direction_data[0]), int(direction_data[1]))
	var width := absi(end.x - start.x) + absi(end.y - start.y)
	var desired := mini(width, 2 if role == PEDESTRIAN_ACCESS else 4)
	var offset := maxi(0, int((width - desired) / 2.0))
	var tangent := Vector2i(signi(end.x - start.x), signi(end.y - start.y))
	var first := start + tangent * offset
	var result: Array[Vector2i] = []
	for step in desired:
		var boundary_point := first + tangent * step
		var inside := boundary_point
		if outward == Vector2i.RIGHT: inside.x = bounds.end.x - 1
		elif outward == Vector2i.DOWN: inside.y = bounds.end.y - 1
		elif outward == Vector2i.LEFT: inside.x = bounds.position.x
		elif outward == Vector2i.UP: inside.y = bounds.position.y
		for cell in [inside, inside + outward]:
			if cell not in result: result.append(cell)
	return result

static func encoded_records(source: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for reservation in source:
		var encoded := reservation.duplicate(true)
		var cells: Array = []
		for cell: Vector2i in reservation.get("cells", []): cells.append([cell.x, cell.y])
		encoded["cells"] = cells
		result.append(encoded)
	result.sort_custom(func(a, b): return str(a.reservation_id) < str(b.reservation_id))
	return result

static func decoded_records(source: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in source:
		if not value is Dictionary: continue
		var record: Dictionary = value.duplicate(true)
		var cells: Array[Vector2i] = []
		for encoded in value.get("cells", []):
			if encoded is Array and encoded.size() == 2: cells.append(Vector2i(int(encoded[0]), int(encoded[1])))
		record["cells"] = cells
		result.append(record)
	return result

static func _normalized_cells(source) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not source is Array: return result
	for value in source:
		var cell: Vector2i
		if value is Vector2i: cell = value
		elif value is Vector3i: cell = Vector2i(value.x, value.z)
		elif value is Array and value.size() == 2: cell = Vector2i(int(value[0]), int(value[1]))
		else: continue
		if cell not in result: result.append(cell)
	result.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	return result

static func reservation_span(record: Dictionary) -> Vector2:
	if record.get("scope", WHOLE_COLUMN) == WHOLE_COLUMN: return Vector2(-INF, INF)
	return Vector2(float(record.elevation), float(record.elevation) + float(record.height))

func _fail(code: String, reservation_id: String, message: String) -> void:
	failures.append({"code": code, "reservation_id": reservation_id, "message": message})
