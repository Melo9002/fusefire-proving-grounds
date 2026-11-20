class_name CylinderPart
extends RefCounted
## Pure prototype geometry for a vertical cylinder: a round tank, silo or column.
##
## Answers the same four questions the box code asks of an AABB, but exactly for a curve:
##   ray_entry     where a shot enters (same value and grazing rules as the box ray test)
##   segment_clear whether a vertical body cylinder can travel along a segment
##   resolve       the closest standing point inside one logical cell
##   contact       the outward direction and desired stand point on the real surface
##
## It never reads or mutates a map, actor or occupancy, and a fit is not permission to
## navigate or occupy a cell: support, routes and neighboring bodies still need validation,
## exactly as for SurfacePlacement. Rounding a result to the canonical 1/10000 tile is the
## caller's job; pass the same absolute tolerance the box code uses (surface_unit / 10000).
##
## Not integrated anywhere yet. Today a round asset is replaced by stepped whole-tile boxes.

const MAX_PARTS := 32
const MAX_CANDIDATES := 256
## Same inset the box ray test uses so open and closed (grazing) probes agree.
const INSET := 0.001

## x/z is the axis; y is the base of the cylinder.
var center := Vector3.ZERO
var radius := 0.0
var height := 0.0

static func create(base_center: Vector3, part_radius: float, part_height: float) -> CylinderPart:
	var part := CylinderPart.new()
	part.center = base_center
	part.radius = part_radius
	part.height = part_height
	return part

func is_valid() -> bool:
	return center.is_finite() and is_finite(radius) and is_finite(height) and radius > 0.0 and height > 0.0

func top() -> float:
	return center.y + height

func axis() -> Vector2:
	return Vector2(center.x, center.z)

## The box the existing code would have used for this part.
func enclosing_bounds() -> AABB:
	return AABB(Vector3(center.x - radius, center.y, center.z - radius), Vector3(radius * 2.0, height, radius * 2.0))

# ---------------------------------------------------------------- shots

## Entry fraction along origin -> destination, or INF. Matches the box ray test: an open
## probe that only grazes the surface misses, a closed probe (tolerant edges) counts the
## graze, and a ray that starts inside enters at 0.
func ray_entry(origin: Vector3, destination: Vector3, closed_edges := false) -> float:
	if not is_valid() or not origin.is_finite() or not destination.is_finite():
		return INF
	var reach := radius + INSET if closed_edges else radius - INSET
	var low := center.y + INSET
	var high := top() - INSET
	if reach <= 0.0 or low >= high:
		return INF
	var enter := 0.0
	var exit := 1.0
	var start := Vector2(origin.x - center.x, origin.z - center.z)
	var delta := Vector2(destination.x - origin.x, destination.z - origin.z)
	if is_zero_approx(delta.x) and is_zero_approx(delta.y):
		if start.length_squared() >= reach * reach:
			return INF
	else:
		var span := _circle_span(start, delta, reach)
		if span.is_empty():
			return INF
		enter = maxf(enter, span[0])
		exit = minf(exit, span[1])
		if enter >= exit:
			return INF
	var rise := destination.y - origin.y
	if is_zero_approx(rise):
		if origin.y <= low or origin.y >= high:
			return INF
	else:
		var first := (low - origin.y) / rise
		var second := (high - origin.y) / rise
		if first > second:
			var swap := first
			first = second
			second = swap
		enter = maxf(enter, first)
		exit = minf(exit, second)
		if enter >= exit:
			return INF
	return enter if exit > 0.0 and enter < 1.0 else INF

# ---------------------------------------------------------------- movement

## True when a vertical body cylinder can move from -> to without entering this part.
## Touching is allowed. tolerance shrinks the required gap by an absolute amount, as the box
## sweep does with surface_unit / PRECISION, so canonically rounded points are not rejected.
func segment_clear(from: Vector3, to: Vector3, body_radius: float, body_height: float, clearance := 0.0, tolerance := 0.000001) -> bool:
	if not is_valid() or not from.is_finite() or not to.is_finite() or not is_finite(body_radius) or not is_finite(body_height) or not is_finite(clearance) or body_radius <= 0.0 or body_height <= 0.0 or clearance < 0.0:
		return false
	var reach := radius + body_radius + clearance - tolerance
	if reach <= 0.0:
		return true
	var enter := 0.0
	var exit := 1.0
	var start := Vector2(from.x - center.x, from.z - center.z)
	var delta := Vector2(to.x - from.x, to.z - from.z)
	if is_zero_approx(delta.x) and is_zero_approx(delta.y):
		if start.length_squared() >= reach * reach:
			return true
	else:
		var span := _circle_span(start, delta, reach)
		if span.is_empty():
			return true
		enter = maxf(enter, span[0])
		exit = minf(exit, span[1])
		if enter >= exit:
			return true
	# The body overlaps the part when its feet are below the top and its head above the base.
	var low := center.y - body_height
	var high := top()
	var rise := to.y - from.y
	if is_zero_approx(rise):
		if from.y <= low or from.y >= high:
			return true
	else:
		var first := (low - from.y) / rise
		var second := (high - from.y) / rise
		if first > second:
			var swap := first
			first = second
			second = swap
		enter = maxf(enter, first)
		exit = minf(exit, second)
		if enter >= exit:
			return true
	return not (exit > 0.0 and enter < 1.0)

# ---------------------------------------------------------------- standing points

## Closest tested fit to a requested point, constrained to its logical cell, with the body
## kept clear of every cylinder. Candidates are exactly the places the closest legal point
## can lie: the requested point itself, its projection onto each margin circle, where margin
## circles cross the cell edges or each other, and the cell corners. The body may extend into
## adjacent open space; later occupancy must check it.
static func resolve(cell_center: Vector3, cylinders: Array[CylinderPart], body_radius := 0.28, body_height := 1.8, clearance := 0.04, cell_size := 1.0, preferred := Vector3.INF) -> Dictionary:
	if not cell_center.is_finite() or not is_finite(body_radius) or not is_finite(body_height) or not is_finite(clearance) or not is_finite(cell_size) or body_radius <= 0.0 or body_height <= 0.0 or clearance < 0.0 or cell_size <= 0.002:
		return {"fits": false, "reason": "Invalid body or cell dimensions"}
	if preferred != Vector3.INF and not preferred.is_finite():
		return {"fits": false, "reason": "Invalid requested point"}
	var wanted: Vector3 = cell_center if preferred == Vector3.INF else preferred
	var half := cell_size * 0.5 - 0.001
	var min_x := cell_center.x - half
	var max_x := cell_center.x + half
	var min_z := cell_center.z - half
	var max_z := cell_center.z + half
	var desired := Vector2(clampf(wanted.x, min_x, max_x), clampf(wanted.z, min_z, max_z))
	var margin := body_radius + clearance
	var local: Array[CylinderPart] = []
	for part in cylinders:
		if part == null or not part.is_valid():
			return {"fits": false, "reason": "Invalid obstacle geometry"}
		# Same vertical rule as the box fit, evaluated at the cell's own level.
		if part.top() <= cell_center.y + 0.001 or part.center.y >= cell_center.y + body_height:
			continue
		var reach := part.radius + margin
		var nearest := Vector2(clampf(part.center.x, min_x, max_x), clampf(part.center.z, min_z, max_z))
		if nearest.distance_squared_to(part.axis()) >= reach * reach:
			continue
		local.append(part)
	if local.size() > MAX_PARTS:
		return {"fits": false, "reason": "Local geometry budget exceeded"}
	var candidates: Array[Vector2] = [desired, Vector2(min_x, min_z), Vector2(min_x, max_z), Vector2(max_x, min_z), Vector2(max_x, max_z)]
	for part in local:
		var reach := part.radius + margin
		var axis_point := part.axis()
		var toward := desired - axis_point
		if toward.length_squared() > 0.0000000001:
			candidates.append(axis_point + toward.normalized() * reach)
		for x: float in [min_x, max_x]:
			var remaining := reach * reach - (x - axis_point.x) * (x - axis_point.x)
			if remaining >= 0.0:
				var spread := sqrt(remaining)
				candidates.append(Vector2(x, axis_point.y - spread))
				candidates.append(Vector2(x, axis_point.y + spread))
		for z: float in [min_z, max_z]:
			var remaining := reach * reach - (z - axis_point.y) * (z - axis_point.y)
			if remaining >= 0.0:
				var spread := sqrt(remaining)
				candidates.append(Vector2(axis_point.x - spread, z))
				candidates.append(Vector2(axis_point.x + spread, z))
	for first in range(local.size()):
		for second in range(first + 1, local.size()):
			candidates.append_array(_circle_crossings(local[first].axis(), local[first].radius + margin, local[second].axis(), local[second].radius + margin))
	var inside: Array[Vector2] = []
	for point in candidates:
		# Crossings are computed with square roots; keep ones that land in the cell and
		# pull the rounding noise back onto it.
		if point.x < min_x - 0.000001 or point.x > max_x + 0.000001 or point.y < min_z - 0.000001 or point.y > max_z + 0.000001:
			continue
		var clamped := Vector2(clampf(point.x, min_x, max_x), clampf(point.y, min_z, max_z))
		if not inside.has(clamped):
			inside.append(clamped)
	inside.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		var da := a.distance_squared_to(desired)
		var db := b.distance_squared_to(desired)
		return da < db if da != db else a.x < b.x or (a.x == b.x and a.y < b.y))
	var tested := 0
	for point in inside:
		if tested >= MAX_CANDIDATES:
			return {"fits": false, "reason": "Standing-point search budget exceeded"}
		tested += 1
		var blocked := false
		for part in local:
			var reach := part.radius + margin
			# Small relative tolerance so a point constructed on the margin circle is not
			# rejected by float noise, as in the box fit.
			if point.distance_squared_to(part.axis()) < reach * reach * 0.99998:
				blocked = true
				break
		if not blocked:
			var position := Vector3(point.x, cell_center.y, point.y)
			return {"fits": true, "position": position, "offset": position - cell_center, "tested": tested, "reason": "Geometric fit only; support, route and occupancy still require validation"}
	return {"fits": false, "reason": "No tested body-sized position fits this cell"}

# ---------------------------------------------------------------- contact

## World-space contact targets for an authored clip plus future procedural fitting, with the
## exact radial normal. Does not move the actor, grant cover, plant feet or solve IK.
func contact(standing_point: Vector3, body_radius := 0.28, body_height := 1.8, clearance := 0.04) -> Dictionary:
	if not is_valid() or not standing_point.is_finite() or not is_finite(body_radius) or not is_finite(body_height) or not is_finite(clearance) or body_radius <= 0.0 or body_height <= 0.0 or clearance < 0.0:
		return {"found": false, "reason": "Invalid contact geometry"}
	if top() <= standing_point.y or center.y >= standing_point.y + body_height:
		return {"found": false, "reason": "Surface is above or below the body"}
	var offset := Vector2(standing_point.x - center.x, standing_point.z - center.z)
	var axis_distance := offset.length()
	if axis_distance <= radius:
		return {"found": false, "reason": "Standing point is inside the footprint"}
	var outward := offset / axis_distance
	var normal := Vector3(outward.x, 0.0, outward.y)
	var surface_height := clampf(standing_point.y + body_height * 0.5, center.y, top())
	var surface_position := Vector3(center.x + outward.x * radius, surface_height, center.z + outward.y * radius)
	var distance := axis_distance - radius
	var desired := Vector3(center.x + outward.x * (radius + body_radius + clearance), standing_point.y, center.z + outward.y * (radius + body_radius + clearance))
	return {"found": true, "surface_position": surface_position, "surface_normal": normal, "direction": -normal, "distance": distance, "desired_stand_point": desired, "surface_bounds": enclosing_bounds(), "body_clear": distance >= body_radius + clearance - 0.000001}

# ---------------------------------------------------------------- helpers

## Parameters [t0, t1] where start + t * delta is inside the circle of this reach around the
## origin; empty when the line misses or only touches it.
static func _circle_span(start: Vector2, delta: Vector2, reach: float) -> Array[float]:
	var a := delta.dot(delta)
	var b := 2.0 * start.dot(delta)
	var c := start.dot(start) - reach * reach
	var discriminant := b * b - 4.0 * a * c
	var result: Array[float] = []
	if discriminant <= 0.0:
		return result
	var root := sqrt(discriminant)
	result.append((-b - root) / (2.0 * a))
	result.append((-b + root) / (2.0 * a))
	return result

static func _circle_crossings(first_center: Vector2, first_radius: float, second_center: Vector2, second_radius: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var between := second_center - first_center
	var distance := between.length()
	if distance < 0.0000001 or distance > first_radius + second_radius or distance < absf(first_radius - second_radius):
		return result
	var along := (first_radius * first_radius - second_radius * second_radius + distance * distance) / (2.0 * distance)
	var height_squared := first_radius * first_radius - along * along
	if height_squared < 0.0:
		return result
	var base := first_center + between / distance * along
	var offset := Vector2(-between.y, between.x) / distance * sqrt(height_squared)
	result.append(base + offset)
	result.append(base - offset)
	return result
