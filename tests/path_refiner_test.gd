extends SceneTree
## Clearance-aware path presentation (pure PathRefiner): direct movement, a rectangular object, an obstacle corner, a narrow passable corridor, a corridor too narrow for the
## body (reported, never "fixed"), a partially obstructed tile, exact endpoints, vertical segments untouched, determinism.
var failures := 0
var checks := 0
const RADIUS := 0.319   # body radius 0.28 + clearance 0.04 - the map's tolerance, as SurfaceNavigation uses it
const HEIGHT := 1.8

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _box(x: float, z: float, w: float, d: float, h := 2.0) -> AABB:
	return AABB(Vector3(x, 0.0, z), Vector3(w, h, d))

func _length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i].distance_to(path[i - 1])
	return total

func _on_original(path: PackedVector3Array, original: PackedVector3Array) -> bool:
	# Every smoothed point lies within the corner's cut of the original polyline (it never wanders away from the authorized route).
	for p in path:
		var near := INF
		for i in range(1, original.size()):
			near = minf(near, p.distance_to(Geometry3D.get_closest_point_to_segment(p, original[i - 1], original[i])))
		if near > 0.2:
			return false
	return true

func _run() -> void:
	var profile := PathPresentationProfile.new()
	profile.enabled = true
	var l_route := PackedVector3Array([Vector3(0, 0, 0), Vector3(3, 0, 0), Vector3(3, 0, 3)])

	# ---- Direct movement, nothing near: corner rounded, endpoints exact, shorter, same ground covered.
	var open := PathRefiner.refine(l_route, [], RADIUS, HEIGHT, profile)
	check(open.path[0] == l_route[0] and open.path[open.path.size() - 1] == l_route[2], "Endpoints are exact")
	check(open.rounded == 1 and open.mismatches.is_empty() and _length(open.path) < _length(l_route), "An unobstructed corner is rounded and the walk is shorter (%.2f < %.2f)" % [_length(open.path), _length(l_route)])
	check(_on_original(open.path, l_route), "The smoothed path stays within the corner's cut of the authorized route")
	var straight := PathRefiner.refine(PackedVector3Array([Vector3(0, 0, 0), Vector3(5, 0, 0)]), [], RADIUS, HEIGHT, profile)
	check(straight.path.size() == 2 and straight.rounded == 0, "A straight segment is left alone")

	# ---- Near a rectangular object: a wall alongside the first leg, 0.55 m off the route.
	var wall := [_box(0.5, 0.55, 2.0, 0.4)]
	var beside := PathRefiner.refine(l_route, wall, RADIUS, HEIGHT, profile)
	check(beside.mismatches.is_empty() and float(beside.min_clearance) >= RADIUS - 0.0001, "Beside a wall the smoothed path keeps the body's clearance (%.3f m of %.3f)" % [beside.min_clearance, RADIUS])

	# ---- Around an obstacle corner: a block fills the inside of the turn, 0.34 m from the route on both legs.
	var inside_block := [_box(0.0, 0.34, 2.66, 2.66)]
	var around := PathRefiner.refine(l_route, inside_block, RADIUS, HEIGHT, profile)
	check(around.mismatches.is_empty() and float(around.min_clearance) >= RADIUS - 0.0001, "Around a block's corner the cut is shrunk or dropped until the clearance holds (%.3f m, %d corner(s) rounded)" % [around.min_clearance, around.rounded])
	check(around.path[0] == l_route[0] and around.path[around.path.size() - 1] == l_route[2], "...with the same endpoints")

	# ---- A narrow but genuinely passable corridor (gap = 2 radius + 0.1) and a route through its middle.
	var gap_ok := 2.0 * RADIUS + 0.1
	var corridor_ok := [_box(0.0, -2.0 - gap_ok * 0.5, 3.5, 2.0), _box(0.0, gap_ok * 0.5, 3.5, 2.0)]
	var through := PathRefiner.refine(PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(5, 0, 0), Vector3(5, 0, 2)]), corridor_ok, RADIUS, HEIGHT, profile)
	check(through.mismatches.is_empty() and float(through.min_clearance) >= RADIUS - 0.0001, "A narrow corridor with %.2f m to spare each side is walked with clearance intact (%.3f m)" % [gap_ok * 0.5 - RADIUS, through.min_clearance])

	# ---- Too narrow for the body: the authorized route is reported, nothing is invented.
	var gap_bad := 2.0 * RADIUS - 0.1
	var corridor_bad := [_box(0.0, -2.0 - gap_bad * 0.5, 6.0, 2.0), _box(0.0, gap_bad * 0.5, 6.0, 2.0)]
	var bad_route := PackedVector3Array([Vector3(0, 0, 0), Vector3(4, 0, 0)])
	var jammed := PathRefiner.refine(bad_route, corridor_bad, RADIUS, HEIGHT, profile)
	check(not jammed.mismatches.is_empty(), "A corridor narrower than the body is reported as a tactical/geometry mismatch (%s)" % [jammed.mismatches])
	check(jammed.path == bad_route, "...and the route is returned unchanged (no silent new route, no teleport)")

	# ---- A partially obstructed tile: a 0.48 m column in the cell; a route past it with clearance is fine, a route through it is a mismatch.
	var column := [_box(-0.24, 1.0 - 0.24, 0.48, 0.48)]
	var past := PathRefiner.refine(PackedVector3Array([Vector3(-2, 0, 0), Vector3(2, 0, 0), Vector3(2, 0, 3)]), column, RADIUS, HEIGHT, profile)
	check(past.mismatches.is_empty() and float(past.min_clearance) >= RADIUS - 0.0001, "Passing a 0.48 m column at %.2f m is allowed and smoothed with clearance" % [float(past.min_clearance)])
	var into := PathRefiner.refine(PackedVector3Array([Vector3(0, 0, -1), Vector3(0, 0, 3)]), column, RADIUS, HEIGHT, profile)
	check(not into.mismatches.is_empty(), "A route through the column is reported")

	# ---- Vertical and stepped segments pass through; parts below the feet and above the head do not block.
	var stepped := PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(2, 1, 0), Vector3(2, 1, 2)])
	var kept := PathRefiner.refine(stepped, [], RADIUS, HEIGHT, profile)
	check(kept.path == stepped and kept.rounded == 0, "A route with a vertical rise is left exactly as it is (ladders, stairs, vaults are not smoothed)")
	check(PathRefiner.segment_clearance(Vector3(0, 0, 0), Vector3(4, 0, 0), [AABB(Vector3(1, 3.0, -0.1), Vector3(1, 1, 0.2))], HEIGHT) == INF, "A part above the head is not an obstacle")
	check(PathRefiner.segment_clearance(Vector3(0, 1, 0), Vector3(4, 1, 0), [AABB(Vector3(1, 0.0, -0.1), Vector3(1, 0.5, 0.2))], HEIGHT) == INF, "A part below the feet is not an obstacle")

	# ---- Determinism and opt-in.
	var again := PathRefiner.refine(l_route, wall, RADIUS, HEIGHT, profile)
	check(again.hash() == beside.hash(), "The same inputs give the same path")
	check(not PathPresentationProfile.new().enabled, "The refinement is opt-in (off by default)")

	print("Path refiner: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
