class_name SurfacePlacement
extends RefCounted
## Pure prototype geometry. A fit is not permission to navigate/occupy a cell.
## Callers supply supported ground and all nearby obstacle bounds in world units.
const MAX_PARTS := 32
const MAX_CANDIDATES := 256

static func _finite(point: Vector3) -> bool:
	return is_finite(point.x) and is_finite(point.y) and is_finite(point.z)

static func _valid_bounds(bounds: AABB) -> bool:
	return _finite(bounds.position) and _finite(bounds.size) and bounds.has_volume()

static func _intersects_body(point: Vector3, bounds: AABB, radius: float, height: float) -> bool:
	if bounds.end.y <= point.y + 0.001 or bounds.position.y >= point.y + height: return false
	var nearest := Vector2(clampf(point.x, bounds.position.x, bounds.end.x), clampf(point.z, bounds.position.z, bounds.end.z))
	return Vector2(point.x, point.z).distance_squared_to(nearest) < radius * radius * 0.999999

## Closest tested fit to a requested point, constrained to its logical cell.
## The body may extend into adjacent open space; later occupancy must check it.
static func resolve(center: Vector3, obstacles: Array[AABB], radius := 0.28, height := 1.8, clearance := 0.04, cell_size := 1.0, preferred := Vector3.INF) -> Dictionary:
	if not _finite(center) or not is_finite(radius) or not is_finite(height) or not is_finite(clearance) or not is_finite(cell_size) or radius <= 0 or height <= 0 or clearance < 0 or cell_size <= 0.002:
		return {"fits": false, "reason": "Invalid body or cell dimensions"}
	if preferred != Vector3.INF and not _finite(preferred): return {"fits": false, "reason": "Invalid requested point"}
	var desired: Vector3 = center if preferred == Vector3.INF else preferred
	var half_cell := cell_size * 0.5 - 0.001
	desired = Vector3(clampf(desired.x, center.x - half_cell, center.x + half_cell), center.y, clampf(desired.z, center.z - half_cell, center.z + half_cell))
	var margin: float = radius + clearance
	var local: Array[AABB] = []
	var search := AABB(center - Vector3(half_cell + margin, 0, half_cell + margin), Vector3(2 * (half_cell + margin), height, 2 * (half_cell + margin)))
	for bounds in obstacles:
		if not _valid_bounds(bounds): return {"fits": false, "reason": "Invalid obstacle bounds"}
		if bounds.intersects(search): local.append(bounds)
	if local.size() > MAX_PARTS: return {"fits": false, "reason": "Local geometry budget exceeded"}
	var xs: Array[float] = [desired.x, center.x - half_cell, center.x + half_cell]
	var zs: Array[float] = [desired.z, center.z - half_cell, center.z + half_cell]
	for bounds in local:
		for x in [bounds.position.x - margin, bounds.end.x + margin]:
			if x >= center.x - half_cell and x <= center.x + half_cell and not xs.has(x): xs.append(x)
		for z in [bounds.position.z - margin, bounds.end.z + margin]:
			if z >= center.z - half_cell and z <= center.z + half_cell and not zs.has(z): zs.append(z)
	var candidates: Array[Vector3] = []
	for x in xs:
		for z in zs:
			var point := Vector3(x, center.y, z)
			if not candidates.has(point): candidates.append(point)
	candidates.sort_custom(func(a: Vector3, b: Vector3):
		var da := a.distance_squared_to(desired)
		var db := b.distance_squared_to(desired)
		return da < db if da != db else a.x < b.x or (a.x == b.x and a.z < b.z))
	var tested := 0
	for point in candidates:
		if tested >= MAX_CANDIDATES: return {"fits": false, "reason": "Standing-point search budget exceeded"}
		tested += 1
		var blocked := false
		for bounds in local:
			if _intersects_body(point, bounds, margin, height):
				blocked = true
				break
		if not blocked: return {"fits": true, "position": point, "offset": point - center, "tested": tested, "reason": "Geometric fit only; support, route and occupancy still require validation"}
	return {"fits": false, "reason": "No tested body-sized position fits this cell"}

## World-space contact targets for an authored clip plus future procedural fitting.
## This does not move the actor, grant cover, plant feet or solve IK.
static func contact(standing_point: Vector3, bounds: AABB, radius := 0.28, height := 1.8, clearance := 0.04) -> Dictionary:
	if not _finite(standing_point) or not _valid_bounds(bounds) or not is_finite(radius) or not is_finite(height) or not is_finite(clearance) or radius <= 0 or height <= 0 or clearance < 0:
		return {"found": false, "reason": "Invalid contact geometry"}
	if bounds.end.y <= standing_point.y or bounds.position.y >= standing_point.y + height:
		return {"found": false, "reason": "Surface is above or below the body"}
	var point := Vector3(clampf(standing_point.x, bounds.position.x, bounds.end.x), clampf(standing_point.y + height * 0.5, bounds.position.y, bounds.end.y), clampf(standing_point.z, bounds.position.z, bounds.end.z))
	var normal := standing_point - point
	normal.y = 0
	if normal.is_zero_approx(): return {"found": false, "reason": "Standing point is inside the footprint"}
	var distance := normal.length()
	normal /= distance
	var desired := point + normal * (radius + clearance)
	desired.y = standing_point.y
	return {"found": true, "surface_position": point, "surface_normal": normal, "direction": -normal, "distance": distance, "desired_stand_point": desired, "surface_bounds": bounds, "body_clear": distance >= radius + clearance - 0.000001}
