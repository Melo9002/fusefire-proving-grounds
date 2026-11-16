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
	data.movement_parts.sort_custom(_bounds_less)
	for cell: MapCellData in data.cells.values():
		if cell.surface_forbidden or not (cell.surface_candidate or (cell.walkable and cell.can_stop)): continue
		var fit := Fit.resolve(cell.support_center, data.movement_parts, data.body_radius, data.body_height, data.body_clearance, unit)
		var valid: bool = fit.fits
		if valid:
			var point: Vector3 = fit.position
			point = (point / unit * PRECISION).round() / PRECISION * unit
			valid = supported(data, point, data.body_radius) and body_clear(data, point)
			if valid: cell.world_position = point
		cell.walkable = valid
		cell.can_stop = valid
		if cell.surface_candidate:
			# Physical parts remain in the independent shot index, never on this floor.
			cell.authored_shot_parts.clear()
			cell.authored_shot_bounds = AABB()
			cell.cover_height = 0.0
			cell.cover_type = MapCellData.CoverType.NONE
			cell.blocks_line_of_sight = false
	data.rebuild_los_index()

static func _bounds_less(a: AABB, b: AABB) -> bool:
	for index in 6:
		var x: float = a.position[index] if index < 3 else a.size[index - 3]
		var y: float = b.position[index] if index < 3 else b.size[index - 3]
		if x != y: return x < y
	return false

static func body_clear(data: MapData, point: Vector3) -> bool:
	for part in data.movement_parts:
		if Fit._intersects_body(point, part, data.body_radius + data.body_clearance - data.surface_unit / PRECISION, data.body_height): return false
	return true

## Whole circular footprint must be on existing floor cells, including at edges.
## Route tolerance permits the existing one-level step/ramp representation.
static func supported(data: MapData, point: Vector3, radius: float, tolerance := 0.001) -> bool:
	if not point.is_finite() or not is_finite(radius) or radius <= 0 or data.surface_unit <= 0: return false
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
	if absf(from.y - to.y) > data.surface_unit + 0.001: return false
	var radius := data.body_radius + data.body_clearance - data.surface_unit / PRECISION
	for part in data.movement_parts:
		var expanded := AABB(part.position - Vector3(radius, data.body_height, radius), part.size + Vector3(radius * 2, data.body_height, radius * 2))
		if segment_enters(from, to, expanded): return false
	var steps := maxi(1, ceili(from.distance_to(to) / (data.surface_unit * 0.1)))
	if steps > 128: return false
	for step in steps + 1:
		if not supported(data, from.lerp(to, float(step) / steps), data.body_radius, 0.501 if from.y != to.y else 0.001): return false
	return true

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

## Actual nearby contacts, including the actor's own cell and diagonal parts.
static func cover_surfaces(data: MapData, point: Vector3) -> Array[MapCellData]:
	var result: Array[MapCellData] = []
	for obstacle in data.shot_obstacles:
		var contact := Fit.contact(point, obstacle.authored_shot_bounds, data.body_radius, data.body_height, data.body_clearance)
		if contact.found and contact.distance <= data.surface_unit * 0.85: result.append(obstacle)
	return result

static func signature(data: MapData) -> String:
	if not data.surface_placement_enabled: return ""
	var records: Array[String] = ["surface-1:10000:%.4f:%.4f:%.4f" % [data.body_radius, data.body_height, data.body_clearance]]
	for part in data.movement_parts:
		var a := (part.position / data.surface_unit * PRECISION).round()
		var b := (part.size / data.surface_unit * PRECISION).round()
		records.append("part=%d,%d,%d,%d,%d,%d" % [a.x, a.y, a.z, b.x, b.y, b.z])
	var keys := data.cells.keys()
	keys.sort_custom(func(a: Vector3i, b: Vector3i): return a.x < b.x or (a.x == b.x and (a.y < b.y or (a.y == b.y and a.z < b.z))))
	for key: Vector3i in keys:
		var cell := data.get_cell(key)
		var p := (cell.world_position / data.surface_unit * PRECISION).round()
		records.append("%d,%d,%d:%d,%d,%d:%d,%d" % [key.x, key.y, key.z, p.x, p.y, p.z, int(cell.walkable), int(cell.can_stop)])
	return "|".join(records).sha256_text()
