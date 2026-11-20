class_name PathRefiner
extends RefCounted
## Smooths the corners of an authorized walking route without leaving the clearance the tactical layer already established. PURE: the route (floor points), the physical parts
## (AABBs, as SurfaceNavigation sees them), the body radius. It returns a polyline with the SAME endpoints that visits the same places, or the original route with a mismatch
## report. It can never authorize anything: a route whose own segments are too close to a part is reported (a geometry/tactical mismatch), never "fixed" by finding another way.
##
## Only horizontal runs (constant floor height) are touched; vertical and stepped segments (ladders, stairs, vaults) pass through unchanged.

const FLAT := 0.01


## Returns {path: PackedVector3Array, sources: Array[int] (for each output point, the index of the original point it belongs to), mismatches: Array[String],
## min_clearance: float (INF when no part is near), rounded: int}.
static func refine(points: PackedVector3Array, parts: Array, radius: float, height: float, profile: PathPresentationProfile) -> Dictionary:
	var result := {"path": points, "sources": [], "mismatches": [], "min_clearance": INF, "rounded": 0}
	var sources: Array[int] = []
	for i in points.size():
		sources.append(i)
	result.sources = sources
	if points.size() < 2:
		return result
	var required := radius + profile.clearance_margin
	# 1. The authorized route itself: every horizontal segment must already clear the parts. If not, report and change nothing.
	var mismatches: Array[String] = []
	var min_clearance := INF
	for i in range(1, points.size()):
		if absf(points[i].y - points[i - 1].y) > FLAT:
			continue
		var clearance := segment_clearance(points[i - 1], points[i], parts, height)
		min_clearance = minf(min_clearance, clearance)
		if clearance < radius - 0.0001:
			mismatches.append("segment %d is %.3f m from a part, closer than the body radius %.3f m (a tactical route the physical geometry does not support)" % [i, clearance, radius])
	if not mismatches.is_empty():
		result.mismatches = mismatches
		result.min_clearance = min_clearance
		return result
	# 2. Round the corners.
	var out := PackedVector3Array()
	var out_sources: Array[int] = []
	out.append(points[0])
	out_sources.append(0)
	var rounded := 0
	for i in range(1, points.size() - 1):
		var corner := _round_corner(points[i - 1], points[i], points[i + 1], parts, height, required, profile)
		if corner.is_empty():
			out.append(points[i])
			out_sources.append(i)
		else:
			rounded += 1
			for point in corner:
				out.append(point)
				out_sources.append(i)
	out.append(points[points.size() - 1])
	out_sources.append(points.size() - 1)
	# 3. The smoothed path's own clearance (never less than the radius: every accepted cut was tested).
	var final_clearance := INF
	for i in range(1, out.size()):
		if absf(out[i].y - out[i - 1].y) <= FLAT:
			final_clearance = minf(final_clearance, segment_clearance(out[i - 1], out[i], parts, height))
	result.path = out
	result.sources = out_sources
	result.min_clearance = final_clearance
	result.rounded = rounded
	return result


## The points replacing corner `v` (between `a` and `b`), or [] when it should stay sharp: not flat, too gentle, no room, or no cut keeps the clearance.
static func _round_corner(a: Vector3, v: Vector3, b: Vector3, parts: Array, height: float, required: float, profile: PathPresentationProfile) -> PackedVector3Array:
	if absf(a.y - v.y) > FLAT or absf(b.y - v.y) > FLAT:
		return PackedVector3Array()
	var in_vector := Vector3(v.x - a.x, 0.0, v.z - a.z)
	var out_vector := Vector3(b.x - v.x, 0.0, b.z - v.z)
	if in_vector.length() < 0.001 or out_vector.length() < 0.001:
		return PackedVector3Array()
	var turn := rad_to_deg(in_vector.angle_to(out_vector))
	if turn < profile.min_turn_degrees:
		return PackedVector3Array()
	var in_dir := in_vector.normalized()
	var out_dir := out_vector.normalized()
	var cut := minf(profile.corner_cut, minf(in_vector.length(), out_vector.length()) * 0.5)
	for attempt in 4:
		if cut < 0.03:
			break
		var start := v - in_dir * cut
		var end := v + out_dir * cut
		var curve := PackedVector3Array()
		for step in range(profile.arc_samples + 1):
			var t := float(step) / float(profile.arc_samples)
			var p := start.lerp(v, t).lerp(v.lerp(end, t), t)   # quadratic Bezier through the corner as its control point
			curve.append(Vector3(p.x, v.y, p.z))
		var ok := true
		for index in range(1, curve.size()):
			if segment_clearance(curve[index - 1], curve[index], parts, height) < required - 0.0001:
				ok = false
				break
		# The straight remainders on either side are parts of the original (already validated) segments.
		if ok:
			return curve
		cut *= 0.5
	return PackedVector3Array()


## The shortest horizontal distance from segment a-b to any part that stands in the body's vertical range (the part's footprint rectangle). INF when no part is near.
static func segment_clearance(a: Vector3, b: Vector3, parts: Array, height: float) -> float:
	var floor_y := minf(a.y, b.y)
	var best := INF
	for part: AABB in parts:
		if part.end.y <= floor_y + 0.05 or part.position.y >= floor_y + height:
			continue   # entirely below the feet or above the head: no obstacle to this body
		best = minf(best, _segment_rect_distance(Vector2(a.x, a.z), Vector2(b.x, b.z), Rect2(part.position.x, part.position.z, part.size.x, part.size.z)))
	return best


static func _segment_rect_distance(a: Vector2, b: Vector2, rect: Rect2) -> float:
	# Zero when the segment touches the rectangle.
	if rect.has_point(a) or rect.has_point(b):
		return 0.0
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var best := INF
	for i in 4:
		var c: Vector2 = corners[i]
		var d: Vector2 = corners[(i + 1) % 4]
		if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
			return 0.0
		for pair in [[a, c, d], [b, c, d], [c, a, b], [d, a, b]]:
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(pair[0], pair[1], pair[2])
			best = minf(best, (pair[0] as Vector2).distance_to(closest))
	return best
