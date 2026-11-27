class_name RoundedPrism
extends CylinderPart
## An upright yawed rounded rectangle. The footprint is the Minkowski sum
## of a local rectangular core and a disk; vertical extent is explicit.

var core := Vector2.ZERO
var yaw := 0.0

static func from_box(base_center: Vector3, half_size: Vector2, corner_radius: float, part_height: float, angle: float) -> RoundedPrism:
	var part := RoundedPrism.new()
	part.center = base_center
	part.core = half_size - Vector2.ONE * corner_radius
	part.radius = corner_radius
	part.height = part_height
	part.yaw = angle
	return part

func is_valid() -> bool:
	return super.is_valid() and core.is_finite() and core.x > 0.0 and core.y > 0.0 and is_finite(yaw)

func enclosing_bounds() -> AABB:
	var c := absf(cos(yaw))
	var s := absf(sin(yaw))
	var reach := Vector2(c * core.x + s * core.y, s * core.x + c * core.y) + Vector2.ONE * radius
	return AABB(center - Vector3(reach.x, 0.0, reach.y), Vector3(2.0 * reach.x, height, 2.0 * reach.y))

func ray_entry(origin: Vector3, destination: Vector3, closed_edges := false, padding := 0.0) -> float:
	return _entry(origin, destination, radius + (INSET if closed_edges else -INSET) + padding, INSET - padding, height - INSET + padding)

func segment_clear(from: Vector3, to: Vector3, body_radius: float, body_height: float, clearance := 0.04, tolerance := 0.0) -> bool:
	return not is_finite(_entry(from, to, radius + body_radius + clearance - tolerance, -body_height, height))

func _entry(from: Vector3, to: Vector3, reach: float, low: float, high: float) -> float:
	if not is_valid() or not from.is_finite() or not to.is_finite() or reach <= 0.0 or low >= high: return INF
	var from_y := from.y - center.y
	var rise := to.y - from.y
	var enter := 0.0
	var exit := 1.0
	if is_zero_approx(rise):
		if from_y <= low or from_y >= high: return INF
	else:
		var a := (low - from_y) / rise
		var b := (high - from_y) / rise
		enter = maxf(enter, minf(a, b))
		exit = minf(exit, maxf(a, b))
		if enter >= exit: return INF
	var start := (Vector2(from.x, from.z) - axis()).rotated(-yaw)
	var delta := Vector2(to.x - from.x, to.z - from.z).rotated(-yaw)
	var best := minf(_strip_entry(start, delta, core + Vector2(reach, 0), enter, exit),
		_strip_entry(start, delta, core + Vector2(0, reach), enter, exit))
	for x in [-core.x, core.x]:
		for z in [-core.y, core.y]:
			var offset := start - Vector2(x, z)
			if delta.length_squared() < 0.000000000001:
				if offset.length_squared() < reach * reach: best = enter
				continue
			var span := _circle_span(offset, delta, reach)
			if not span.is_empty() and maxf(enter, span[0]) < minf(exit, span[1]):
				best = minf(best, maxf(enter, span[0]))
	return best

static func _strip_entry(start: Vector2, delta: Vector2, half: Vector2, enter: float, exit: float) -> float:
	for i in 2:
		if is_zero_approx(delta[i]):
			if absf(start[i]) >= half[i]: return INF
		else:
			var a := (-half[i] - start[i]) / delta[i]
			var b := (half[i] - start[i]) / delta[i]
			enter = maxf(enter, minf(a, b))
			exit = minf(exit, maxf(a, b))
			if enter >= exit: return INF
	return enter

func contact(standing_point: Vector3, body_radius := 0.28, body_height := 1.8, clearance := 0.04) -> Dictionary:
	if not is_valid() or not standing_point.is_finite() or standing_point.y >= top() or standing_point.y + body_height <= center.y:
		return {"found": false}
	var local := (Vector2(standing_point.x, standing_point.z) - axis()).rotated(-yaw)
	var nearest := local.clamp(-core, core)
	var offset := local - nearest
	var length := offset.length()
	if length <= radius: return {"found": false}
	var normal := offset / length
	var horizontal := axis() + (nearest + normal * radius).rotated(yaw)
	normal = normal.rotated(yaw)
	var outward := Vector3(normal.x, 0, normal.y)
	var surface := Vector3(horizontal.x, clampf(standing_point.y + body_height * 0.5, center.y, top()), horizontal.y)
	var desired := surface + outward * (body_radius + clearance)
	desired.y = standing_point.y
	return {"found": true, "surface_position": surface, "surface_normal": outward, "direction": -outward,
		"distance": length - radius, "desired_stand_point": desired, "surface_bounds": enclosing_bounds(),
		"body_clear": length - radius >= body_radius + clearance - 0.000001}

func geometry_record(unit: float) -> String:
	return "rounded:%s:%s:%s" % [super.geometry_record(unit), (core / unit * 10000.0).round(), roundi(yaw * 1000000.0)]
