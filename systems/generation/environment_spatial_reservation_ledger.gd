class_name EnvironmentSpatialReservationLedger
extends RefCounted
## Deterministic construction-time reservations. These records protect mission
## and functional access space; they never author MapData occupancy themselves.

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
	if reservations.any(func(existing): return existing.reservation_id == reservation_id):
		_fail("DUPLICATE_RESERVATION", reservation_id, "reservation identity is already present")
		return false
	for existing in reservations:
		if _cells_intersect(cells, existing.cells) and not roles_are_compatible(role, str(existing.role), owner_ref, str(existing.owner_ref)):
			_fail("INCOMPATIBLE_RESERVATION", reservation_id, "%s conflicts with %s" % [reservation_id, existing.reservation_id])
			return false
	record["cells"] = cells
	record["required"] = bool(record.get("required", true))
	record["validation_state"] = str(record.get("validation_state", "validated"))
	reservations.append(record)
	reservations.sort_custom(func(a, b): return str(a.reservation_id) < str(b.reservation_id))
	return true

func placement_allowed(definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement, layout: EnvironmentModuleLayout, owner_ref := "") -> Dictionary:
	if definition.placement_layer == EnvironmentModuleDefinition.PlacementLayer.GROUND:
		return {"ok": true}
	var occupied := layout.world_cells(definition, placement)
	occupied.append_array(layout.world_clearance_cells(definition, placement))
	var visual_bounds := layout.world_visual_envelope(definition, placement) if definition.tactical_role == EnvironmentModuleDefinition.TacticalRole.VISUAL_ONLY else AABB()
	for reservation in reservations:
		if _cells_intersect(occupied, reservation.cells) or _visual_intersects_cells(visual_bounds, reservation.cells):
			return {
				"ok": false,
				"code": "RESERVED_REGION_BLOCKED",
				"reservation_id": reservation.reservation_id,
				"owner_ref": owner_ref,
				"message": "%s intrudes into required %s '%s'" % [placement.component_id, reservation.role, reservation.reservation_id],
			}
	return {"ok": true}

func contains(role: String, cell: Vector2i) -> bool:
	return reservations.any(func(record): return record.role == role and record.cells.has(cell))

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
	var offset := maxi(0, (width - desired) / 2)
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

static func _cells_intersect(first: Array, second: Array) -> bool:
	for cell in first:
		if second.has(cell): return true
	return false

static func _visual_intersects_cells(bounds: AABB, cells: Array) -> bool:
	if bounds.size == Vector3.ZERO: return false
	for cell: Vector2i in cells:
		if bounds.position.x < float(cell.x + 1) and bounds.end.x > float(cell.x) and bounds.position.z < float(cell.y + 1) and bounds.end.z > float(cell.y):
			return true
	return false

func _fail(code: String, reservation_id: String, message: String) -> void:
	failures.append({"code": code, "reservation_id": reservation_id, "message": message})
