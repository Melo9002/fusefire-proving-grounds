class_name SurfaceNavigation
extends RefCounted
## One cell, one supported point. Conservative box sweeps; no physics timing/RNG.
const Fit = preload("res://systems/grid/surface_placement.gd")
const PRECISION := 10000.0

static func resolve_map(data: MapData, unit: float) -> void:
	if not data.surface_placement_enabled: return
	data.surface_unit = unit
	data.body_radius = 0.28 * unit
	data.body_height = 1.8 * unit
	data.body_clearance = 0.04 * unit
	data.movement_routes.clear()
	data.movement_parts.sort_custom(_bounds_less)
	_rebuild_movement_index(data)
	for cell: MapCellData in data.cells.values():
		if cell.surface_forbidden or not (cell.surface_candidate or (cell.walkable and cell.can_stop)): continue
		cell.is_vault_transit = false
		cell.world_position = cell.support_center
		cell.elevation = cell.support_center.y
		var fit := Fit.resolve(cell.support_center, _local_parts(data, cell.support_center, cell.support_center, unit * 0.5 + data.body_radius + data.body_clearance), data.body_radius, data.body_height, data.body_clearance, unit, Vector3.INF, true)
		var valid: bool = fit.fits
		if valid:
			var point: Vector3 = fit.position
			point = (point / unit * PRECISION).round() / PRECISION * unit
			valid = supported(data, point, data.body_radius) and _sweep_clear(data, point, point, true)
			if valid: cell.world_position = point
		cell.walkable = valid
		cell.can_stop = valid
		# Preserve existing low-cover traversal, but place its transit checkpoint
		# above the physical part and validate entry/exit instead of clipping it.
		if not valid and cell.cover_type == MapCellData.CoverType.LOW:
			var raised := cell.support_center
			raised.y += cell.cover_height + data.body_clearance
			raised = (raised / unit * PRECISION).round() / PRECISION * unit
			if body_clear(data, raised):
				cell.world_position = raised
				cell.elevation = raised.y
				cell.is_vault_transit = true
				cell.walkable = true
		if cell.surface_candidate:
			# Physical parts remain in the independent shot index, never on this floor.
			cell.authored_shot_parts.clear()
			cell.authored_shot_bounds = AABB()
			if not cell.is_vault_transit:
				cell.cover_height = 0.0
				cell.cover_type = MapCellData.CoverType.NONE
			cell.blocks_line_of_sight = false
	data.rebuild_los_index()
	data.surface_points_resolved = true

static func _bounds_less(a: AABB, b: AABB) -> bool:
	for index in 6:
		var x: float = a.position[index] if index < 3 else a.size[index - 3]
		var y: float = b.position[index] if index < 3 else b.size[index - 3]
		if x != y: return x < y
	return false

static func body_clear(data: MapData, point: Vector3) -> bool:
	for part in _local_parts(data, point, point, data.body_radius + data.body_clearance):
		if Fit._intersects_body(point, part, data.body_radius + data.body_clearance - data.surface_unit / PRECISION, data.body_height, true): return false
	return true

## Whole circular footprint must be on existing floor cells, including at edges.
## Route tolerance permits the existing one-level step/ramp representation.
static func supported(data: MapData, point: Vector3, radius: float, tolerance := 0.001) -> bool:
	if not point.is_finite() or not is_finite(radius) or radius <= 0 or data.surface_unit <= 0: return false
	if _vault_at(data, point): return body_clear(data, point)
	var unit := data.surface_unit
	var half := Vector2(data.map_size) * 0.5
	for x in range(floori((point.x - radius) / unit + half.x), floori((point.x + radius) / unit + half.x) + 1):
		for z in range(floori((point.z - radius) / unit + half.y), floori((point.z + radius) / unit + half.y) + 1):
			var nearest := Vector2(clampf(point.x, (x - half.x) * unit, (x + 1 - half.x) * unit), clampf(point.z, (z - half.y) * unit, (z + 1 - half.y) * unit))
			if nearest.distance_squared_to(Vector2(point.x, point.z)) >= radius * radius * 0.999999: continue
			var found := false
			for floor_cell: MapCellData in data.columns.get(Vector2i(x, z), []):
				if floor_cell.support_surface and absf(floor_cell.support_center.y - point.y) <= tolerance * unit:
					found = true
					break
			if not found: return false
	return true

## Sweeps an enclosing body box. This may reject a tight rounded corner, never
## accept a route on the strength of destination clearance alone.
static func edge_clear(data: MapData, from: Vector3, to: Vector3) -> bool:
	if not data.surface_placement_enabled: return true
	var route := traversal_route(data, from, to)
	if route.size() > 2:
		if not supported(data, from, data.body_radius) or not supported(data, to, data.body_radius): return false
		for index in range(1, route.size()):
			if not _sweep_clear(data, route[index - 1], route[index], false): return false
		return true
	return _sweep_clear(data, from, to, true)

## An explicit ladder supplies support during traversal. Rise outside the upper
## floor first, then step onto it; descending follows the same route in reverse.
static func traversal_route(data: MapData, from: Vector3, to: Vector3) -> PackedVector3Array:
	var cacheable := data.surface_points_resolved and data.movement_index_count == data.movement_parts.size()
	var key := [Vector3i((from / data.surface_unit * PRECISION).round()), Vector3i((to / data.surface_unit * PRECISION).round()), Vector4(data.body_radius, data.body_height, data.body_clearance, data.surface_unit)]
	if cacheable and data.movement_routes.has(key): return data.movement_routes[key]
	var route := _compute_traversal_route(data, from, to)
	if cacheable: data.movement_routes[key] = route
	return route

static func _compute_traversal_route(data: MapData, from: Vector3, to: Vector3) -> PackedVector3Array:
	if not is_equal_approx(from.y, to.y):
		if _vault_at(data, from) or _vault_at(data, to):
			var low := from if from.y < to.y else to
			var high := to if from.y < to.y else from
			return PackedVector3Array([from, Vector3(low.x, high.y, low.z), to])
		for link in data.traversal_links:
			var a := data.get_cell(link.from_cell)
			var b := data.get_cell(link.to_cell)
			if not a or not b: continue
			var forward := a.world_position.is_equal_approx(from) and b.world_position.is_equal_approx(to)
			var backward := link.bidirectional and b.world_position.is_equal_approx(from) and a.world_position.is_equal_approx(to)
			if forward or backward:
				var low := from if from.y < to.y else to
				var high := to if from.y < to.y else from
				return PackedVector3Array([from, Vector3(low.x, high.y, low.z), to])
	if is_equal_approx(from.y, to.y):
		var radius := data.body_radius + data.body_clearance - data.surface_unit / PRECISION
		var peak := from.y
		var blocked := false
		var low_only := true
		for part in _local_parts(data, from, to, radius):
			var expanded := AABB(part.position - Vector3(radius, data.body_height, radius), part.size + Vector3(radius * 2, data.body_height, radius * 2))
			if not segment_enters(from, to, expanded): continue
			blocked = true
			if part.end.y - from.y >= data.surface_unit * 1.2: low_only = false
			peak = maxf(peak, part.end.y + data.body_clearance)
		if blocked:
			# A within-edge elbow can enter a gap without cutting a box corner.
			# Both floor and body clearance are checked, not just the endpoints.
			for elbow in [Vector3(from.x, from.y, to.z), Vector3(to.x, from.y, from.z)]:
				if elbow.is_equal_approx(from) or elbow.is_equal_approx(to): continue
				if _sweep_clear(data, from, elbow, true) and _sweep_clear(data, elbow, to, true): return PackedVector3Array([from, elbow, to])
		if blocked and low_only and peak > from.y:
			return PackedVector3Array([from, Vector3(from.x, peak, from.z), Vector3(to.x, peak, to.z), to])
	return PackedVector3Array([from, to])

static func _vault_at(data: MapData, point: Vector3) -> bool:
	var key := Vector2i(floori(point.x / data.surface_unit + data.map_size.x * 0.5), floori(point.z / data.surface_unit + data.map_size.y * 0.5))
	for cell: MapCellData in data.columns.get(key, []):
		if cell.is_vault_transit and cell.world_position.is_equal_approx(point): return true
	return false

static func _sweep_clear(data: MapData, from: Vector3, to: Vector3, require_floor: bool) -> bool:
	if require_floor and absf(from.y - to.y) > data.surface_unit + 0.001: return false
	var radius := data.body_radius + data.body_clearance - data.surface_unit / PRECISION
	for part in _local_parts(data, from, to, radius):
		var expanded := AABB(part.position - Vector3(radius, data.body_height, radius), part.size + Vector3(radius * 2, data.body_height, radius * 2))
		if segment_enters(from, to, expanded): return false
	if not require_floor: return true
	if is_equal_approx(from.y, to.y):
		# The swept enclosing box needs a supported footprint. Check each floor
		# tile once rather than resampling the same floor every tenth metre.
		var half := Vector2(data.map_size) * 0.5
		for x in range(floori((minf(from.x, to.x) - data.body_radius) / data.surface_unit + half.x), floori((maxf(from.x, to.x) + data.body_radius) / data.surface_unit + half.x) + 1):
			for z in range(floori((minf(from.z, to.z) - data.body_radius) / data.surface_unit + half.y), floori((maxf(from.z, to.z) + data.body_radius) / data.surface_unit + half.y) + 1):
				var found := false
				for floor_cell: MapCellData in data.columns.get(Vector2i(x, z), []):
					if floor_cell.support_surface and absf(floor_cell.support_center.y - from.y) <= 0.001 * data.surface_unit:
						found = true
						break
				if not found: return false
		return true
	var steps := maxi(1, ceili(from.distance_to(to) / (data.surface_unit * 0.1)))
	if steps > 128: return false
	for step in steps + 1:
		if not supported(data, from.lerp(to, float(step) / steps), data.body_radius, 0.501 if from.y != to.y else 0.001): return false
	return true

## Compiled geometry is immutable until the next compilation/resolution pass.
static func _rebuild_movement_index(data: MapData) -> void:
	data.movement_columns.clear()
	data.movement_index_count = data.movement_parts.size()
	var half := Vector2(data.map_size) * 0.5
	for index in data.movement_parts.size():
		var part := data.movement_parts[index]
		for x in range(floori(part.position.x / data.surface_unit + half.x), ceili(part.end.x / data.surface_unit + half.x)):
			for z in range(floori(part.position.z / data.surface_unit + half.y), ceili(part.end.z / data.surface_unit + half.y)):
				var key := Vector2i(x, z)
				if not data.movement_columns.has(key): data.movement_columns[key] = []
				data.movement_columns[key].append(index)

static func _local_parts(data: MapData, from: Vector3, to: Vector3, margin: float) -> Array[AABB]:
	if data.movement_index_count != data.movement_parts.size(): return data.movement_parts
	var half := Vector2(data.map_size) * 0.5
	var found := {}
	for x in range(floori((minf(from.x, to.x) - margin) / data.surface_unit + half.x), floori((maxf(from.x, to.x) + margin) / data.surface_unit + half.x) + 1):
		for z in range(floori((minf(from.z, to.z) - margin) / data.surface_unit + half.y), floori((maxf(from.z, to.z) + margin) / data.surface_unit + half.y) + 1):
			for index in data.movement_columns.get(Vector2i(x, z), []): found[index] = true
	var indices := found.keys()
	indices.sort()
	var result: Array[AABB] = []
	for index in indices: result.append(data.movement_parts[index])
	return result

static func segment_enters(from: Vector3, to: Vector3, bounds: AABB) -> bool:
	var enter := 0.0
	var exit := 1.0
	for axis in 3:
		var delta: float = to[axis] - from[axis]
		var low: float = bounds.position[axis] + 0.000001
		var high: float = bounds.end[axis] - 0.000001
		if absf(delta) < 0.0000001:
			if from[axis] <= low or from[axis] >= high: return false
		else:
			var a: float = (low - from[axis]) / delta
			var b: float = (high - from[axis]) / delta
			enter = maxf(enter, minf(a, b))
			exit = minf(exit, maxf(a, b))
			if enter >= exit: return false
	return exit > 0 and enter < 1

static func units_clear(grid: GridManager, from: Vector3, to: Vector3, ignored: TacticalUnit = null) -> bool:
	if not grid.map_data.surface_placement_enabled: return true
	var route := traversal_route(grid.map_data, from, to)
	for index in range(1, route.size()):
		if not _unit_segment_clear(grid, route[index - 1], route[index], ignored): return false
	return true

static func _unit_segment_clear(grid: GridManager, from: Vector3, to: Vector3, ignored: TacticalUnit) -> bool:
	var data := grid.map_data
	if not data.surface_placement_enabled: return true
	var gap := data.body_radius * 2 + data.body_clearance
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	for other: TacticalUnit in grid.occupancy_map.values():
		if not is_instance_valid(other) or other == ignored: continue
		var cell := data.get_cell(other.grid_position)
		if not cell: return false
		var point := cell.world_position
		if point.y >= maxf(from.y, to.y) + data.body_height or point.y + data.body_height <= minf(from.y, to.y): continue
		var p := Vector2(point.x, point.z)
		var nearest := Geometry2D.get_closest_point_to_segment(p, a, b)
		if p.distance_squared_to(nearest) < gap * gap * 0.999999: return false
	return true

## How far from a standing point the real wall of a round asset still counts as a contact,
## in tiles. Round assets reserve whole tiles that still grant tactical cover, and a free tile beside a
## reserved diagonal corner can be about 1.7 tiles from the real wall, so the reach must match.
const ROUND_REACH_UNITS := 1.75

## Presentation-only contacts with the real wall of round assets (MapData.presentation_*).
## Cover markers and pose contacts use these; tactics (cover, shots, standing points) never do.
static func presentation_contacts(data: MapData, point: Vector3, reach: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for part in data.presentation_cylinders:
		var contact := part.contact(point, data.body_radius, data.body_height, data.body_clearance)
		if contact.found and contact.distance <= reach:
			result.append({"contact": contact, "top": part.top(), "cylinder": part})
	for bounds in data.presentation_boxes:
		var contact := Fit.contact(point, bounds, data.body_radius, data.body_height, data.body_clearance)
		if contact.found and contact.distance <= reach:
			result.append({"contact": contact, "top": bounds.end.y, "bounds": bounds})
	return result

## Actual nearby contacts, including the actor's own cell and diagonal parts.
static func cover_surfaces(data: MapData, point: Vector3) -> Array[MapCellData]:
	var result: Array[MapCellData] = []
	var reach := data.surface_unit * 0.85
	var half := Vector2(data.map_size) * 0.5
	for x in range(floori((point.x - reach) / data.surface_unit + half.x), floori((point.x + reach) / data.surface_unit + half.x) + 1):
		for z in range(floori((point.z - reach) / data.surface_unit + half.y), floori((point.z + reach) / data.surface_unit + half.y) + 1):
			var key := Vector2i(x, z)
			for obstacle: MapCellData in data.shot_columns.get(key, []) + data.columns.get(key, []):
				if obstacle.cover_type == MapCellData.CoverType.NONE or not obstacle.authored_shot_bounds.has_volume(): continue
				var contact := Fit.contact(point, obstacle.authored_shot_bounds, data.body_radius, data.body_height, data.body_clearance)
				if contact.found and contact.distance <= reach: result.append(obstacle)
	return result

static func signature(data: MapData) -> String:
	if not data.surface_placement_enabled: return ""
	var records: Array[String] = ["surface-2:10000:%.4f:%.4f:%.4f" % [data.body_radius, data.body_height, data.body_clearance]]
	for part in data.movement_parts:
		var a := (part.position / data.surface_unit * PRECISION).round()
		var b := (part.size / data.surface_unit * PRECISION).round()
		records.append("part=%d,%d,%d,%d,%d,%d" % [a.x, a.y, a.z, b.x, b.y, b.z])
	var keys := data.cells.keys()
	keys.sort_custom(func(a: Vector3i, b: Vector3i): return a.x < b.x or (a.x == b.x and (a.y < b.y or (a.y == b.y and a.z < b.z))))
	for key: Vector3i in keys:
		var cell := data.get_cell(key)
		var p := (cell.world_position / data.surface_unit * PRECISION).round()
		records.append("%d,%d,%d:%d,%d,%d:%d,%d,%d" % [key.x, key.y, key.z, p.x, p.y, p.z, int(cell.walkable), int(cell.can_stop), int(cell.is_vault_transit)])
	return "|".join(records).sha256_text()
