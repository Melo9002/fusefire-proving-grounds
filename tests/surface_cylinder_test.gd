extends SceneTree
## Round-asset geometry core (pure). A cylinder must answer ray, sweep, fit and contact
## questions exactly, agree with the box rules where they overlap, and beat them where a
## box cannot (a diagonal approach to a round wall).
const Cylinder = preload("res://systems/grid/cylinder_part.gd")
const Fit = preload("res://systems/grid/surface_placement.gd")
const BODY_RADIUS := 0.28
const BODY_HEIGHT := 1.8
const CLEARANCE := 0.04

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _near(a: float, b: float, tolerance := 0.0005) -> bool:
	return absf(a - b) <= tolerance

func _tank() -> CylinderPart:
	return Cylinder.create(Vector3.ZERO, 2.0, 3.0)

func _run() -> void:
	_ray()
	_sweep()
	_fit()
	_contact()
	_invariants()
	print("Surface cylinder geometry: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _ray() -> void:
	var tank := _tank()
	check(tank.is_valid() and tank.enclosing_bounds() == AABB(Vector3(-2, 0, -2), Vector3(4, 3, 4)), "Enclosing bounds are the box the old code used")
	check(_near(tank.ray_entry(Vector3(-5, 1, 0), Vector3(5, 1, 0)), 0.3), "A ray through the axis enters at the real surface")
	check(is_inf(tank.ray_entry(Vector3(-5, 1, 2.0), Vector3(5, 1, 2.0))), "An open probe that only grazes the surface misses")
	check(not is_inf(tank.ray_entry(Vector3(-5, 1, 2.0), Vector3(5, 1, 2.0), true)), "A closed probe counts the graze, as for boxes")
	check(is_inf(tank.ray_entry(Vector3(-5, 1, 2.2), Vector3(5, 1, 2.2), true)), "A closed probe still misses beyond the tolerance")
	var offset_entry := tank.ray_entry(Vector3(-5, 1, 1.8), Vector3(5, 1, 1.8))
	check(_near(offset_entry, (5.0 - sqrt(4.0 - 1.8 * 1.8)) / 10.0, 0.002), "An off-axis ray enters on the curve, not at the enclosing box face (a box would enter at 0.3)")
	check(is_inf(tank.ray_entry(Vector3(-5, 3.5, 0), Vector3(5, 3.5, 0))) and is_inf(tank.ray_entry(Vector3(-5, -0.5, 0), Vector3(5, -0.5, 0))), "Rays above or below the part miss it")
	check(_near(tank.ray_entry(Vector3(-5, 3.5, 0), Vector3(5, 0.5, 0)), 0.3, 0.02), "A descending ray that is within the height at the wall enters")
	check(is_inf(tank.ray_entry(Vector3(-5, 4.5, 0), Vector3(5, 3.2, 0))), "A ray that stays above the top throughout misses")
	check(tank.ray_entry(Vector3(0, 1, 0), Vector3(5, 1, 0)) == 0.0, "A ray that starts inside enters at zero")
	check(is_inf(tank.ray_entry(Vector3(-5, 1, 0), Vector3(-3, 1, 0))), "A segment that ends before the surface misses")
	check(_near(tank.ray_entry(Vector3(0.5, -1, 0), Vector3(0.5, 4, 0)), 0.2, 0.001), "A vertical segment enters through the base plane")
	check(is_inf(tank.ray_entry(Vector3(3, -1, 0), Vector3(3, 4, 0))), "A vertical segment outside the radius misses")
	check(is_inf(Cylinder.create(Vector3.ZERO, 0.0, 3.0).ray_entry(Vector3(-5, 1, 0), Vector3(5, 1, 0))), "An invalid cylinder never blocks a ray")

func _sweep() -> void:
	var tank := _tank()
	var gap := BODY_RADIUS + CLEARANCE
	check(tank.segment_clear(Vector3(-5, 0, 2.0 + gap + 0.01), Vector3(5, 0, 2.0 + gap + 0.01), BODY_RADIUS, BODY_HEIGHT, CLEARANCE), "A body passing just outside the required gap is clear")
	check(not tank.segment_clear(Vector3(-5, 0, 2.0 + gap - 0.02), Vector3(5, 0, 2.0 + gap - 0.02), BODY_RADIUS, BODY_HEIGHT, CLEARANCE), "A body passing inside the required gap is blocked")
	check(tank.segment_clear(Vector3(-5, 0, 2.0 + gap), Vector3(5, 0, 2.0 + gap), BODY_RADIUS, BODY_HEIGHT, CLEARANCE), "Touching the required gap is allowed")
	check(tank.segment_clear(Vector3(-5, 0, 2.0 + gap - 0.00005), Vector3(5, 0, 2.0 + gap - 0.00005), BODY_RADIUS, BODY_HEIGHT, CLEARANCE, 0.0001), "A canonical rounding tolerance absorbs 1/10000 tile of rounding")
	check(not tank.segment_clear(Vector3(-5, 0, 0), Vector3(5, 0, 0), BODY_RADIUS, BODY_HEIGHT, CLEARANCE), "A path through the middle is blocked")
	check(tank.segment_clear(Vector3(-5, 0, 0), Vector3(-3, 0, 0), BODY_RADIUS, BODY_HEIGHT, CLEARANCE), "A path that stops short is clear")
	check(not tank.segment_clear(Vector3(2.2, 0, 0), Vector3(2.2, 0, 0), BODY_RADIUS, BODY_HEIGHT, CLEARANCE), "A standing body too close to the wall is blocked, even with no travel")
	check(tank.segment_clear(Vector3(2.4, 0, 0), Vector3(2.4, 0, 0), BODY_RADIUS, BODY_HEIGHT, CLEARANCE), "A standing body beside the wall at the right distance is clear")
	check(tank.segment_clear(Vector3(-5, 3.0, 0), Vector3(5, 3.0, 0), BODY_RADIUS, BODY_HEIGHT, CLEARANCE), "A body whose feet are at the top passes over it")
	check(not tank.segment_clear(Vector3(-5, 2.9, 0), Vector3(5, 2.9, 0), BODY_RADIUS, BODY_HEIGHT, CLEARANCE), "A body whose feet are just below the top is blocked")
	check(tank.segment_clear(Vector3(-5, -1.9, 0), Vector3(5, -1.9, 0), BODY_RADIUS, BODY_HEIGHT, CLEARANCE), "A body entirely below the part is clear")
	var diagonal := Vector3(1.0, 0, 1.0).normalized() * (2.0 + gap + 0.01)
	check(tank.segment_clear(diagonal, diagonal, BODY_RADIUS, BODY_HEIGHT, CLEARANCE), "Standing at the diagonal is clear at the same radial distance as at a cardinal point")
	check(not tank.segment_clear(Vector3.ZERO, Vector3.ZERO, 0.0, BODY_HEIGHT, CLEARANCE), "An invalid body is never reported clear")

func _fit() -> void:
	var tank := _tank()
	var tanks: Array[CylinderPart] = [tank]
	var margin := BODY_RADIUS + CLEARANCE
	var reach := 2.0 + margin
	var far := Cylinder.resolve(Vector3(5.5, 0, 0), tanks)
	check(far.fits and far.position == Vector3(5.5, 0, 0), "A cell far from the part keeps its centre")
	var beside := Cylinder.resolve(Vector3(2.2, 0, 0), tanks)
	check(beside.fits and _near(beside.position.x, reach, 0.001) and _near(beside.position.z, 0.0), "A partly covered cell stands the body beside the curved wall")
	var inside := Cylinder.resolve(Vector3.ZERO, tanks)
	check(not inside.fits, "A cell inside the part has no standing point")

	# The headline difference: a diagonal approach.
	var diagonal_cell := Vector3(1.6, 0, 1.6)
	var curved := Cylinder.resolve(diagonal_cell, tanks)
	check(curved.fits and _near(Vector2(curved.position.x, curved.position.z).length(), reach, 0.001), "A diagonal cell stands exactly one body-margin from the curved wall")
	var boxes: Array[AABB] = [tank.enclosing_bounds()]
	var boxed := Fit.resolve(diagonal_cell, boxes, BODY_RADIUS, BODY_HEIGHT, CLEARANCE, 1.0)
	check(not boxed.fits, "The enclosing box leaves no legal point inside that diagonal cell, so the tile is lost today")
	# Census: every cell in a ring around the part. The curve must never lose a cell the box keeps.
	var box_usable := 0
	var curve_usable := 0
	var lost_by_box_only := 0
	for ix in range(-4, 4):
		for iz in range(-4, 4):
			var ring_cell := Vector3(ix + 0.5, 0, iz + 0.5)
			var with_box: bool = Fit.resolve(ring_cell, boxes, BODY_RADIUS, BODY_HEIGHT, CLEARANCE, 1.0).fits
			var with_curve: bool = Cylinder.resolve(ring_cell, tanks).fits
			box_usable += int(with_box)
			curve_usable += int(with_curve)
			if with_box and not with_curve:
				check(false, "The curve loses a cell the box keeps: %s" % ring_cell)
			if with_curve and not with_box:
				lost_by_box_only += 1
	print("[Cylinder] 8x8 cells around a radius-2 tank: usable with the enclosing box %d, with the curve %d (%d recovered)" % [box_usable, curve_usable, lost_by_box_only])
	check(curve_usable > box_usable and lost_by_box_only >= 4, "The curve recovers at least the four diagonal cells the box throws away")

	# Closest-fit property by brute force over the cell.
	var cell := Vector3(1.6, 0, 1.6)
	var best := INF
	var step := 0.01
	var x := cell.x - 0.499
	while x <= cell.x + 0.499:
		var z := cell.z - 0.499
		while z <= cell.z + 0.499:
			if Vector2(x, z).length() >= reach * 0.99998:
				best = minf(best, Vector2(x, z).distance_to(Vector2(cell.x, cell.z)))
			z += step
		x += step
	check(curved.fits and Vector2(curved.position.x, curved.position.z).distance_to(Vector2(cell.x, cell.z)) <= best + 0.01, "No legal point in the cell is meaningfully closer to the requested one than the fit")

	# A passage between two round parts.
	var wide: Array[CylinderPart] = [Cylinder.create(Vector3(-2.5, 0, 0), 2.0, 3.0), Cylinder.create(Vector3(2.5, 0, 0), 2.0, 3.0)]
	check(Cylinder.resolve(Vector3.ZERO, wide).fits, "A passage wider than the body has a standing point at its middle")
	var tight: Array[CylinderPart] = [Cylinder.create(Vector3(-2.1, 0, 0), 2.0, 3.0), Cylinder.create(Vector3(2.1, 0, 0), 2.0, 3.0)]
	check(not Cylinder.resolve(Vector3.ZERO, tight).fits, "An undersized passage is rejected instead of relying on animation to hide clipping")
	var reversed := tight.duplicate()
	reversed.reverse()
	check(Cylinder.resolve(Vector3.ZERO, tight) == Cylinder.resolve(Vector3.ZERO, reversed), "Obstacle ordering does not change the result")
	var pinch: Array[CylinderPart] = [Cylinder.create(Vector3(-1.9, 0.0, 1.35), 1.0, 3.0), Cylinder.create(Vector3(1.9, 0.0, 1.35), 1.0, 3.0)]
	var pinched := Cylinder.resolve(Vector3(0, 0, 0.4), pinch)
	check(pinched.fits, "A cell between two round parts finds the point where their margins leave room")

	# Height rules.
	var overhead: Array[CylinderPart] = [Cylinder.create(Vector3(0, 2.3, 0), 2.0, 0.5)]
	check(Cylinder.resolve(Vector3.ZERO, overhead).position == Vector3.ZERO, "A beam safely overhead does not consume ground standing room")
	var low: Array[CylinderPart] = [Cylinder.create(Vector3(0, -1, 0), 2.0, 0.5)]
	check(Cylinder.resolve(Vector3.ZERO, low).position == Vector3.ZERO, "A part entirely below the floor does not consume standing room")

	# Invalid input.
	check(not Cylinder.resolve(Vector3.ZERO, tanks, 0.0).fits and not Cylinder.resolve(Vector3(INF, 0, 0), tanks).fits, "Invalid body or cell dimensions are rejected")
	var broken: Array[CylinderPart] = [Cylinder.create(Vector3.ZERO, -1.0, 3.0)]
	check(not Cylinder.resolve(Vector3(3, 0, 0), broken).fits, "An invalid obstacle is rejected rather than ignored")
	var crowd: Array[CylinderPart] = []
	for index in Cylinder.MAX_PARTS + 1:
		crowd.append(Cylinder.create(Vector3(0.0001 * index, 0, 0), 0.6, 2.0))
	check(Cylinder.resolve(Vector3.ZERO, crowd).reason.contains("budget"), "A crowded cell reports the geometry budget instead of guessing")

func _contact() -> void:
	var tank := _tank()
	var tanks: Array[CylinderPart] = [tank]
	var margin := BODY_RADIUS + CLEARANCE
	var stand := Vector3(cos(PI * 0.25), 0, sin(PI * 0.25)) * (2.0 + margin)
	var contact := tank.contact(stand, BODY_RADIUS, BODY_HEIGHT, CLEARANCE)
	check(contact.found and contact.body_clear, "A body at the margin has a clear contact")
	if contact.found:
		var normal := Vector3(cos(PI * 0.25), 0, sin(PI * 0.25))
		check(contact.surface_normal.is_equal_approx(normal) and contact.direction.is_equal_approx(-normal), "The contact normal is exactly radial, here at 45 degrees (a box can only report an axis)")
		check(contact.surface_position.is_equal_approx(Vector3(normal.x * 2.0, 0.9, normal.z * 2.0)), "The contact target lies on the real curved wall at mid-body height")
		check(_near(contact.distance, margin, 0.0001) and contact.desired_stand_point.is_equal_approx(stand), "Contact preserves body radius plus clearance")
	check(not tank.contact(Vector3(1, 0, 0)).found and not tank.contact(Vector3(5, 3.5, 0)).found and not tank.contact(Vector3(5, -2, 0)).found, "Inside the footprint, above and below the part give no contact")
	check(not tank.contact(Vector3(2.2, 0, 0)).body_clear, "A body too close to the wall is reported as not clear")
	var fit := Cylinder.resolve(Vector3(1.6, 0, 1.6), tanks)
	var resolved := tank.contact(fit.position, BODY_RADIUS, BODY_HEIGHT, CLEARANCE)
	check(fit.fits and resolved.found and resolved.body_clear and resolved.desired_stand_point.is_equal_approx(fit.position), "A resolved point and its contact agree: the fit is exactly where the contact says to stand")

func _invariants() -> void:
	var tank := _tank()
	var tanks: Array[CylinderPart] = [tank]
	check(Cylinder.resolve(Vector3(1.6, 0, 1.6), tanks) == Cylinder.resolve(Vector3(1.6, 0, 1.6), tanks), "The same inputs give the same result")
	var shift := Vector3(7.25, 0.4, -3.5)
	var moved: Array[CylinderPart] = [Cylinder.create(shift, 2.0, 3.0)]
	var base := Cylinder.resolve(Vector3(1.6, 0, 1.6), tanks)
	var translated := Cylinder.resolve(Vector3(1.6, 0, 1.6) + shift, moved)
	check(base.fits and translated.fits and (translated.position - shift).is_equal_approx(base.position), "A translated scene gives the translated fit")
	check(_near(tank.ray_entry(Vector3(-5, 1, 0), Vector3(5, 1, 0)), moved[0].ray_entry(Vector3(-5, 1, 0) + shift, Vector3(5, 1, 0) + shift)), "Ray entry is translation invariant")
	# Radial symmetry: the margin distance is the same at every angle.
	for degrees in [0, 17, 45, 90, 133, 200, 271]:
		var angle := deg_to_rad(float(degrees))
		var direction := Vector3(cos(angle), 0, sin(angle))
		var probe := direction * (2.0 + BODY_RADIUS + CLEARANCE + 0.5)
		var cell := Cylinder.resolve(direction * 2.2, tanks, BODY_RADIUS, BODY_HEIGHT, CLEARANCE, 1.0, direction * 2.2)
		if cell.fits:
			check(_near(Vector2(cell.position.x, cell.position.z).length(), 2.0 + BODY_RADIUS + CLEARANCE, 0.0015), "The fit keeps the same distance to the wall at %d degrees" % degrees)
		else:
			check(false, "A cell beside the wall has a fit at %d degrees" % degrees)
		check(tank.segment_clear(probe, probe, BODY_RADIUS, BODY_HEIGHT, CLEARANCE), "A body at that distance is clear at %d degrees" % degrees)
